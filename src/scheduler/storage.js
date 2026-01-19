/**
 * スケジュール設定のGCSストレージ v2
 * 
 * gs://youbun-sqlite/config/schedules.json に設定を保存・読み込み
 * 
 * v2の変更点:
 * - ジョブ単位での管理
 * - 1ジョブに複数スケジュール
 * - GUI設定（daily/interval）
 * - 日付範囲指定
 * - データマート自動実行オプション
 */

import { Storage } from '@google-cloud/storage';

const storage = new Storage();
const BUCKET_NAME = 'youbun-sqlite';
const CONFIG_PATH = 'config/schedules.json';
const MAX_HISTORY = 100;
const CURRENT_VERSION = 2;

/**
 * スケジュールからcron式を生成
 */
export const scheduleToCron = (schedule) => {
    if (schedule.type === 'daily') {
        const minute = schedule.minute ?? 0;
        const hour = schedule.hour ?? 0;
        return `${minute} ${hour} * * *`;
    } else if (schedule.type === 'interval') {
        const hours = schedule.intervalHours ?? 6;
        return `0 */${hours} * * *`;
    }
    return '0 0 * * *'; // デフォルト
};

/**
 * スケジュールの説明文を生成
 */
export const describeSchedule = (schedule) => {
    if (schedule.type === 'daily') {
        const hour = String(schedule.hour ?? 0).padStart(2, '0');
        const minute = String(schedule.minute ?? 0).padStart(2, '0');
        return `毎日 ${hour}:${minute}`;
    } else if (schedule.type === 'interval') {
        return `${schedule.intervalHours ?? 6}時間ごと`;
    }
    return '不明';
};

/**
 * デフォルトのジョブ設定
 */
export const DEFAULT_JOBS = [
    {
        id: 'priority_scrape',
        name: '優先店舗スクレイピング',
        description: '高優先度店舗（lateUpdate: true）のデータを取得',
        jobType: 'scrape',
        enabled: true,
        runDatamartAfter: true,
        dateRange: { from: 1, to: 1 },
        options: { prioritizeHigh: true, continueOnError: true },
        schedules: [
            {
                id: 'priority_daily',
                type: 'daily',
                hour: 23,
                minute: 30,
                enabled: true,
            },
        ],
    },
    {
        id: 'normal_scrape',
        name: '通常店舗スクレイピング',
        description: '全店舗の未取得データを取得',
        jobType: 'scrape',
        enabled: true,
        runDatamartAfter: true,
        dateRange: { from: 1, to: 1 },
        options: { prioritizeHigh: false, continueOnError: true },
        schedules: [
            {
                id: 'normal_daily',
                type: 'daily',
                hour: 0,
                minute: 30,
                enabled: true,
            },
        ],
    },
    {
        id: 'datamart_update',
        name: 'データマート更新',
        description: 'BigQueryのmachine_statsテーブルを更新',
        jobType: 'datamart',
        enabled: true,
        runDatamartAfter: false,
        dateRange: { from: 1, to: 1 },
        options: {},
        schedules: [
            {
                id: 'datamart_daily',
                type: 'daily',
                hour: 1,
                minute: 0,
                enabled: true,
            },
        ],
    },
];

/**
 * v1形式からv2形式にマイグレーション
 */
const migrateV1toV2 = (v1Config) => {
    console.log('スケジュール設定をv1からv2にマイグレーションします...');
    
    const jobs = v1Config.schedules.map(oldSchedule => {
        // cron式をパース（簡易的）
        const cronParts = (oldSchedule.cron || '0 0 * * *').split(' ');
        const minute = parseInt(cronParts[0]) || 0;
        const hour = parseInt(cronParts[1]) || 0;
        
        return {
            id: oldSchedule.id,
            name: oldSchedule.name,
            description: oldSchedule.description || '',
            jobType: oldSchedule.jobType || 'scrape',
            enabled: oldSchedule.enabled ?? true,
            runDatamartAfter: oldSchedule.jobType === 'scrape',
            dateRange: { from: 1, to: 1 },
            options: oldSchedule.options || {},
            schedules: [
                {
                    id: `${oldSchedule.id}_daily`,
                    type: 'daily',
                    hour,
                    minute,
                    enabled: true,
                },
            ],
        };
    });
    
    return {
        version: CURRENT_VERSION,
        updatedAt: new Date().toISOString(),
        jobs,
        history: v1Config.history || [],
    };
};

/**
 * GCSから設定を読み込み
 */
export const loadConfig = async () => {
    try {
        const bucket = storage.bucket(BUCKET_NAME);
        const file = bucket.file(CONFIG_PATH);
        
        const [exists] = await file.exists();
        if (!exists) {
            console.log('スケジュール設定が存在しません。デフォルト設定を使用します。');
            return {
                version: CURRENT_VERSION,
                updatedAt: new Date().toISOString(),
                jobs: DEFAULT_JOBS,
                history: [],
            };
        }
        
        const [content] = await file.download();
        const config = JSON.parse(content.toString());
        
        // バージョンチェックとマイグレーション
        if (!config.version || config.version < CURRENT_VERSION) {
            const migratedConfig = migrateV1toV2(config);
            await saveConfig(migratedConfig);
            return migratedConfig;
        }
        
        console.log(`スケジュール設定を読み込みました: ${config.jobs.length}件のジョブ`);
        return config;
    } catch (error) {
        console.error('スケジュール設定の読み込みに失敗しました:', error.message);
        return {
            version: CURRENT_VERSION,
            updatedAt: new Date().toISOString(),
            jobs: DEFAULT_JOBS,
            history: [],
        };
    }
};

/**
 * GCSに設定を保存
 */
export const saveConfig = async (config) => {
    try {
        const bucket = storage.bucket(BUCKET_NAME);
        const file = bucket.file(CONFIG_PATH);
        
        // 履歴を制限
        if (config.history && config.history.length > MAX_HISTORY) {
            config.history = config.history.slice(-MAX_HISTORY);
        }
        
        config.version = CURRENT_VERSION;
        config.updatedAt = new Date().toISOString();
        
        await file.save(JSON.stringify(config, null, 2), {
            contentType: 'application/json',
        });
        console.log('スケジュール設定を保存しました');
    } catch (error) {
        console.error('スケジュール設定の保存に失敗しました:', error.message);
        throw error;
    }
};

/**
 * ジョブを取得
 */
export const getJob = async (jobId) => {
    const config = await loadConfig();
    return config.jobs.find(j => j.id === jobId);
};

/**
 * ジョブを更新
 */
export const updateJob = async (jobId, updates) => {
    const config = await loadConfig();
    const jobIndex = config.jobs.findIndex(j => j.id === jobId);
    
    if (jobIndex === -1) {
        throw new Error(`ジョブが見つかりません: ${jobId}`);
    }
    
    // schedulesは個別のAPIで更新するので、ここでは除外
    const { schedules, ...otherUpdates } = updates;
    
    config.jobs[jobIndex] = {
        ...config.jobs[jobIndex],
        ...otherUpdates,
    };
    
    await saveConfig(config);
    return config.jobs[jobIndex];
};

/**
 * ジョブにスケジュールを追加
 */
export const addSchedule = async (jobId, schedule) => {
    const config = await loadConfig();
    const job = config.jobs.find(j => j.id === jobId);
    
    if (!job) {
        throw new Error(`ジョブが見つかりません: ${jobId}`);
    }
    
    // IDを自動生成
    const newSchedule = {
        id: `schedule_${Date.now()}`,
        type: 'daily',
        hour: 0,
        minute: 0,
        enabled: true,
        ...schedule,
    };
    
    job.schedules = job.schedules || [];
    job.schedules.push(newSchedule);
    
    await saveConfig(config);
    return newSchedule;
};

/**
 * スケジュールを更新
 */
export const updateSchedule = async (jobId, scheduleId, updates) => {
    const config = await loadConfig();
    const job = config.jobs.find(j => j.id === jobId);
    
    if (!job) {
        throw new Error(`ジョブが見つかりません: ${jobId}`);
    }
    
    const scheduleIndex = job.schedules.findIndex(s => s.id === scheduleId);
    if (scheduleIndex === -1) {
        throw new Error(`スケジュールが見つかりません: ${scheduleId}`);
    }
    
    job.schedules[scheduleIndex] = {
        ...job.schedules[scheduleIndex],
        ...updates,
    };
    
    await saveConfig(config);
    return job.schedules[scheduleIndex];
};

/**
 * スケジュールを削除
 */
export const deleteSchedule = async (jobId, scheduleId) => {
    const config = await loadConfig();
    const job = config.jobs.find(j => j.id === jobId);
    
    if (!job) {
        throw new Error(`ジョブが見つかりません: ${jobId}`);
    }
    
    const scheduleIndex = job.schedules.findIndex(s => s.id === scheduleId);
    if (scheduleIndex === -1) {
        throw new Error(`スケジュールが見つかりません: ${scheduleId}`);
    }
    
    job.schedules.splice(scheduleIndex, 1);
    
    await saveConfig(config);
    return { success: true };
};

/**
 * 実行履歴を追加
 */
export const addHistory = async (historyEntry) => {
    const config = await loadConfig();
    
    config.history = config.history || [];
    config.history.push({
        ...historyEntry,
        timestamp: new Date().toISOString(),
    });
    
    await saveConfig(config);
};

/**
 * 実行履歴を取得
 */
export const getHistory = async (limit = 20) => {
    const config = await loadConfig();
    return (config.history || [])
        .slice(-limit)
        .reverse();
};

export default {
    loadConfig,
    saveConfig,
    getJob,
    updateJob,
    addSchedule,
    updateSchedule,
    deleteSchedule,
    addHistory,
    getHistory,
    scheduleToCron,
    describeSchedule,
    DEFAULT_JOBS,
    CURRENT_VERSION,
};
