/**
 * スケジューラー v2
 * 
 * - 複数スケジュールの登録
 * - 日付範囲対応
 * - スクレイピング後のデータマート自動実行
 */

import cron from 'node-cron';
import { 
    loadConfig, 
    saveConfig,
    addHistory,
    scheduleToCron,
    describeSchedule,
} from './storage.js';
import { runScrape } from '../app.js';
import { runDatamartUpdate } from '../services/datamart/runner.js';
import { getJSTToday } from '../util/date.js';
import { acquireLock, releaseLock, getLockStatus } from '../util/lock.js';
import stateManager from '../api/state-manager.js';

// アクティブなcronジョブを保持
const cronJobs = new Map();
let currentConfig = null;
let bigqueryClient = null;
let sqliteDb = null;

/**
 * スケジューラーを初期化
 */
export const initScheduler = async (bigquery, db) => {
    bigqueryClient = bigquery;
    sqliteDb = db;
    
    console.log('スケジューラーを初期化しています...');
    
    try {
        currentConfig = await loadConfig();
        
        // 全てのジョブのスケジュールを登録
        for (const job of currentConfig.jobs) {
            if (job.enabled) {
                registerJobSchedules(job);
            }
        }
        
        const totalSchedules = currentConfig.jobs.reduce(
            (sum, job) => sum + (job.schedules?.length || 0), 0
        );
        console.log(`スケジューラー初期化完了: ${currentConfig.jobs.length}件のジョブ, ${totalSchedules}件のスケジュール`);
    } catch (error) {
        console.error('スケジューラー初期化中にエラー:', error.message);
    }
};

/**
 * ジョブのスケジュールを登録
 */
const registerJobSchedules = (job) => {
    // 既存のスケジュールを解除
    unregisterJobSchedules(job.id);
    
    if (!job.schedules || job.schedules.length === 0) {
        console.log(`[${job.name}] スケジュールがありません`);
        return;
    }
    
    for (const schedule of job.schedules) {
        if (!schedule.enabled) {
            continue;
        }
        
        const cronExpression = scheduleToCron(schedule);
        const jobKey = `${job.id}:${schedule.id}`;
        
        console.log(`[${job.name}] スケジュール登録: ${describeSchedule(schedule)} (${cronExpression})`);
        
        const cronJob = cron.schedule(cronExpression, () => {
            executeJob(job).catch(error => {
                console.error(`[${job.name}] 実行エラー:`, error);
            });
        }, {
            timezone: 'Asia/Tokyo',
        });
        
        cronJobs.set(jobKey, cronJob);
    }
};

/**
 * ジョブのスケジュールを解除
 */
const unregisterJobSchedules = (jobId) => {
    for (const [key, cronJob] of cronJobs.entries()) {
        if (key.startsWith(`${jobId}:`)) {
            cronJob.stop();
            cronJobs.delete(key);
        }
    }
};

/**
 * 日付範囲から対象日付の配列を生成
 */
const getTargetDates = (dateRange) => {
    const today = getJSTToday();
    const dates = [];
    
    const from = dateRange?.from ?? 1;
    const to = dateRange?.to ?? 1;
    
    // fromの方が大きい数値（より古い日付）
    for (let i = from; i >= to; i--) {
        const date = new Date(today);
        date.setDate(date.getDate() - i);
        dates.push(date.toISOString().split('T')[0]);
    }
    
    return dates;
};

/**
 * ジョブを実行
 */
export const executeJob = async (job, options = {}) => {
    const { manual = false } = options;
    const startedAt = new Date().toISOString();
    
    console.log(`[スケジューラー] ジョブ開始: ${job.name}${manual ? ' (手動実行)' : ''}`);
    
    let status = 'success';
    let message = '';
    let details = {};
    
    try {
        // ロック確認
        const lockAcquired = await acquireLock();
        if (!lockAcquired) {
            const lockStatus = await getLockStatus();
            status = 'skipped';
            message = `別の処理が実行中のためスキップ (${lockStatus?.environment || '不明'})`;
            console.log(`[スケジューラー] ${message}`);
            await addHistory({
                jobId: job.id,
                jobName: job.name,
                startedAt,
                finishedAt: new Date().toISOString(),
                status,
                message,
                details,
                manual,
            });
            return { success: false, status, message };
        }
        
        try {
            if (job.jobType === 'scrape') {
                // スクレイピング実行
                const targetDates = getTargetDates(job.dateRange);
                console.log(`[${job.name}] 対象日付: ${targetDates.join(', ')}`);
                
                stateManager.startJob('scraping');
                
                let totalSuccess = 0;
                let totalFailed = 0;
                let totalSkipped = 0;
                
                for (const targetDate of targetDates) {
                    const updateProgress = (current, total, msg) => {
                        stateManager.updateProgress('scraping', current, total, `[${targetDate}] ${msg}`);
                    };
                    
                    const result = await runScrape(bigqueryClient, sqliteDb, updateProgress, {
                        startDate: targetDate,
                        endDate: targetDate,
                        continueOnError: job.options?.continueOnError ?? true,
                        force: false,
                        prioritizeHigh: job.options?.prioritizeHigh ?? false,
                    });
                    
                    totalSuccess += result.success.length;
                    totalFailed += result.failed.length;
                    totalSkipped += result.skipped.length;
                }
                
                message = `成功=${totalSuccess}, 失敗=${totalFailed}, スキップ=${totalSkipped}`;
                details = { success: totalSuccess, failed: totalFailed, skipped: totalSkipped, targetDates };
                
                stateManager.completeJob('scraping', message);
                
                // データマート自動更新
                if (job.runDatamartAfter && totalSuccess > 0) {
                    console.log(`[${job.name}] データマートを自動更新します...`);
                    stateManager.startJob('datamart');
                    
                    try {
                        for (const targetDate of targetDates) {
                            await runDatamartUpdate(targetDate);
                        }
                        message += ', データマート更新完了';
                        stateManager.completeJob('datamart', 'スクレイピング後の自動更新完了');
                    } catch (dmError) {
                        console.error(`[${job.name}] データマート更新エラー:`, dmError.message);
                        message += `, データマート更新失敗: ${dmError.message}`;
                        stateManager.failJob('datamart', dmError.message);
                    }
                }
                
            } else if (job.jobType === 'datamart') {
                // データマート更新
                const targetDates = getTargetDates(job.dateRange);
                console.log(`[${job.name}] 対象日付: ${targetDates.join(', ')}`);
                
                stateManager.startJob('datamart');
                
                for (const targetDate of targetDates) {
                    const result = await runDatamartUpdate(targetDate);
                    details.jobId = result.jobId;
                }
                
                message = `データマート更新完了 (${targetDates.length}日分)`;
                details.targetDates = targetDates;
                
                stateManager.completeJob('datamart', message);
            }
            
            console.log(`[スケジューラー] ジョブ完了: ${job.name} - ${message}`);
            
        } catch (error) {
            status = 'failed';
            message = error.message;
            console.error(`[スケジューラー] ジョブ失敗: ${job.name}`, error);
            
            if (job.jobType === 'scrape') {
                stateManager.failJob('scraping', error.message);
            } else if (job.jobType === 'datamart') {
                stateManager.failJob('datamart', error.message);
            }
        } finally {
            await releaseLock();
        }
        
    } catch (error) {
        status = 'failed';
        message = error.message;
        console.error(`[スケジューラー] ジョブ実行中にエラー: ${job.name}`, error);
    }
    
    // 履歴に記録
    await addHistory({
        jobId: job.id,
        jobName: job.name,
        startedAt,
        finishedAt: new Date().toISOString(),
        status,
        message,
        details,
        manual,
    });
    
    return { success: status === 'success', status, message, details };
};

/**
 * ジョブを手動実行
 */
export const runJobManually = async (jobId) => {
    // 最新の設定を読み込み
    currentConfig = await loadConfig();
    const job = currentConfig.jobs.find(j => j.id === jobId);
    
    if (!job) {
        throw new Error(`ジョブが見つかりません: ${jobId}`);
    }
    
    return executeJob(job, { manual: true });
};

/**
 * スケジュールを再読み込み
 */
export const reloadSchedules = async () => {
    console.log('スケジュールを再読み込みしています...');
    
    // 全てのcronジョブを停止
    for (const [key, cronJob] of cronJobs.entries()) {
        cronJob.stop();
    }
    cronJobs.clear();
    
    // 設定を再読み込み
    currentConfig = await loadConfig();
    
    // スケジュールを再登録
    for (const job of currentConfig.jobs) {
        if (job.enabled) {
            registerJobSchedules(job);
        }
    }
    
    console.log('スケジュール再読み込み完了');
};

/**
 * 現在の設定を取得
 */
export const getConfig = () => currentConfig;

/**
 * スケジューラーを停止
 */
export const stopScheduler = () => {
    console.log('スケジューラーを停止しています...');
    
    for (const [key, cronJob] of cronJobs.entries()) {
        cronJob.stop();
    }
    cronJobs.clear();
    
    console.log('スケジューラー停止完了');
};

export default {
    initScheduler,
    executeJob,
    runJobManually,
    reloadSchedules,
    getConfig,
    stopScheduler,
};
