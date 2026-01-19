/**
 * スケジューラーモジュール
 * 
 * node-cronを使用してスクレイピングとデータマート更新を定期実行
 */

import cron from 'node-cron';
import { loadConfig, saveConfig, addHistory } from './storage.js';
import { runScrape } from '../app.js';
import { runDatamartUpdate } from '../services/datamart/runner.js';
import { acquireLock, releaseLock, getLockStatus } from '../util/lock.js';
import { getJSTYesterday } from '../util/date.js';
import stateManager from '../api/state-manager.js';

// 登録済みジョブを保持
const jobs = new Map();

// 現在の設定
let currentConfig = null;

/**
 * スケジューラーを初期化
 * @param {object} bigquery - BigQueryクライアント
 * @param {object} db - SQLiteデータベース
 */
export const initScheduler = async (bigquery, db) => {
    console.log('スケジューラーを初期化しています...');
    
    try {
        currentConfig = await loadConfig();
        
        for (const schedule of currentConfig.schedules) {
            if (schedule.enabled) {
                registerJob(schedule, bigquery, db);
            }
        }
        
        console.log(`スケジューラー初期化完了: ${jobs.size}件のジョブを登録`);
    } catch (error) {
        console.error('スケジューラーの初期化に失敗しました:', error.message);
    }
};

/**
 * ジョブを登録
 * @param {object} schedule - スケジュール設定
 * @param {object} bigquery - BigQueryクライアント
 * @param {object} db - SQLiteデータベース
 */
const registerJob = (schedule, bigquery, db) => {
    // 既存ジョブがあれば停止
    if (jobs.has(schedule.id)) {
        jobs.get(schedule.id).stop();
        console.log(`既存ジョブを停止: ${schedule.id}`);
    }
    
    // cron式が有効かチェック
    if (!cron.validate(schedule.cron)) {
        console.error(`無効なcron式: ${schedule.cron} (${schedule.id})`);
        return;
    }
    
    // ジョブを登録
    const job = cron.schedule(schedule.cron, async () => {
        console.log(`[スケジューラー] ジョブ開始: ${schedule.name}`);
        await executeJob(schedule, bigquery, db);
    }, {
        timezone: 'Asia/Tokyo',
    });
    
    jobs.set(schedule.id, job);
    console.log(`ジョブ登録: ${schedule.name} (${schedule.cron})`);
};

/**
 * ジョブを実行
 * @param {object} schedule - スケジュール設定
 * @param {object} bigquery - BigQueryクライアント
 * @param {object} db - SQLiteデータベース
 */
const executeJob = async (schedule, bigquery, db) => {
    const startedAt = new Date().toISOString();
    let status = 'success';
    let message = '';
    let details = {};
    
    try {
        // ロックを取得
        const lockAcquired = await acquireLock();
        if (!lockAcquired) {
            const lockStatus = await getLockStatus();
            status = 'skipped';
            message = `別の処理が実行中のためスキップ (${lockStatus?.environment || '不明'})`;
            console.log(`[スケジューラー] ${message}`);
        } else {
            try {
                if (schedule.jobType === 'scrape') {
                    // スクレイピング実行
                    const targetDate = getJSTYesterday();
                    const updateProgress = (current, total, msg) => {
                        stateManager.updateProgress('scraping', current, total, msg);
                    };
                    
                    stateManager.startJob('scraping');
                    
                    const result = await runScrape(bigquery, db, updateProgress, {
                        startDate: targetDate,
                        endDate: targetDate,
                        continueOnError: schedule.options?.continueOnError ?? true,
                        force: false,
                        prioritizeHigh: schedule.options?.prioritizeHigh ?? false,
                    });
                    
                    message = `成功=${result.success.length}, 失敗=${result.failed.length}, スキップ=${result.skipped.length}`;
                    details = {
                        success: result.success.length,
                        failed: result.failed.length,
                        skipped: result.skipped.length,
                        targetDate,
                    };
                    
                    stateManager.completeJob('scraping', message);
                    
                } else if (schedule.jobType === 'datamart') {
                    // データマート更新
                    const targetDate = getJSTYesterday();
                    
                    stateManager.startJob('datamart');
                    
                    const result = await runDatamartUpdate(targetDate);
                    
                    message = `データマート更新完了 (jobId: ${result.jobId})`;
                    details = {
                        jobId: result.jobId,
                        targetDate: result.targetDate,
                    };
                    
                    stateManager.completeJob('datamart', message);
                }
                
                console.log(`[スケジューラー] ジョブ完了: ${schedule.name} - ${message}`);
                
            } catch (error) {
                status = 'failed';
                message = error.message;
                console.error(`[スケジューラー] ジョブ失敗: ${schedule.name}`, error);
                
                if (schedule.jobType === 'scrape') {
                    stateManager.failJob('scraping', error.message);
                } else if (schedule.jobType === 'datamart') {
                    stateManager.failJob('datamart', error.message);
                }
            } finally {
                await releaseLock();
            }
        }
    } catch (error) {
        status = 'failed';
        message = error.message;
        console.error(`[スケジューラー] ジョブエラー: ${schedule.name}`, error);
    }
    
    // 履歴を保存
    await addHistory({
        scheduleId: schedule.id,
        scheduleName: schedule.name,
        jobType: schedule.jobType,
        startedAt,
        finishedAt: new Date().toISOString(),
        status,
        message,
        details,
    });
};

/**
 * 手動でジョブを実行
 * @param {string} scheduleId - スケジュールID
 * @param {object} bigquery - BigQueryクライアント
 * @param {object} db - SQLiteデータベース
 * @returns {Promise<object>} 実行結果
 */
export const runJobManually = async (scheduleId, bigquery, db) => {
    if (!currentConfig) {
        currentConfig = await loadConfig();
    }
    
    const schedule = currentConfig.schedules.find(s => s.id === scheduleId);
    if (!schedule) {
        throw new Error(`スケジュールが見つかりません: ${scheduleId}`);
    }
    
    console.log(`[スケジューラー] 手動実行開始: ${schedule.name}`);
    await executeJob(schedule, bigquery, db);
    
    return { success: true, scheduleId, scheduleName: schedule.name };
};

/**
 * スケジュール設定を更新してジョブを再登録
 * @param {string} scheduleId - スケジュールID
 * @param {object} updates - 更新内容
 * @param {object} bigquery - BigQueryクライアント
 * @param {object} db - SQLiteデータベース
 * @returns {Promise<object>} 更新後のスケジュール
 */
export const updateScheduleAndReload = async (scheduleId, updates, bigquery, db) => {
    // 設定を更新
    currentConfig = await loadConfig();
    const scheduleIndex = currentConfig.schedules.findIndex(s => s.id === scheduleId);
    
    if (scheduleIndex === -1) {
        throw new Error(`スケジュールが見つかりません: ${scheduleId}`);
    }
    
    currentConfig.schedules[scheduleIndex] = {
        ...currentConfig.schedules[scheduleIndex],
        ...updates,
    };
    
    await saveConfig(currentConfig);
    
    const schedule = currentConfig.schedules[scheduleIndex];
    
    // ジョブを再登録
    if (jobs.has(scheduleId)) {
        jobs.get(scheduleId).stop();
    }
    
    if (schedule.enabled) {
        registerJob(schedule, bigquery, db);
    } else {
        jobs.delete(scheduleId);
        console.log(`ジョブ無効化: ${schedule.name}`);
    }
    
    return schedule;
};

/**
 * 現在のスケジュール状態を取得
 * @returns {Promise<Array>} スケジュール一覧（次回実行時刻付き）
 */
export const getScheduleStatus = async () => {
    if (!currentConfig) {
        currentConfig = await loadConfig();
    }
    
    return currentConfig.schedules.map(schedule => {
        const job = jobs.get(schedule.id);
        let nextRun = null;
        
        if (job && schedule.enabled) {
            // node-cronのnextDate()は存在しないので、cronstrue等で計算が必要
            // 簡易的にcron式を返す
            nextRun = schedule.cron;
        }
        
        return {
            ...schedule,
            isRegistered: jobs.has(schedule.id),
            nextRun,
        };
    });
};

/**
 * スケジューラーを停止
 */
export const stopScheduler = () => {
    for (const [id, job] of jobs) {
        job.stop();
        console.log(`ジョブ停止: ${id}`);
    }
    jobs.clear();
    console.log('スケジューラーを停止しました');
};

export default {
    initScheduler,
    runJobManually,
    updateScheduleAndReload,
    getScheduleStatus,
    stopScheduler,
};
