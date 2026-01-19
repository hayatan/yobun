/**
 * スケジュール設定のGCSストレージ
 * 
 * gs://youbun-sqlite/config/schedules.json に設定を保存・読み込み
 */

import { Storage } from '@google-cloud/storage';

const storage = new Storage();
const BUCKET_NAME = 'youbun-sqlite';
const CONFIG_PATH = 'config/schedules.json';
const MAX_HISTORY = 100;

/**
 * デフォルトのスケジュール設定
 */
export const DEFAULT_SCHEDULES = [
    {
        id: 'priority_scrape',
        name: '優先店舗スクレイピング',
        description: '高優先度店舗（lateUpdate: true）のデータを取得',
        cron: '30 23 * * *',  // JST 23:30
        enabled: true,
        jobType: 'scrape',
        options: {
            prioritizeHigh: true,
            continueOnError: true,
        },
    },
    {
        id: 'normal_scrape',
        name: '通常店舗スクレイピング',
        description: '全店舗の未取得データを取得',
        cron: '30 0 * * *',   // JST 00:30
        enabled: true,
        jobType: 'scrape',
        options: {
            prioritizeHigh: false,
            continueOnError: true,
        },
    },
    {
        id: 'datamart_update',
        name: 'データマート更新',
        description: 'BigQueryのmachine_statsテーブルを更新',
        cron: '0 1 * * *',    // JST 01:00
        enabled: true,
        jobType: 'datamart',
        options: {},
    },
];

/**
 * GCSから設定を読み込み
 * @returns {Promise<object>} スケジュール設定
 */
export const loadConfig = async () => {
    try {
        const bucket = storage.bucket(BUCKET_NAME);
        const file = bucket.file(CONFIG_PATH);
        
        const [exists] = await file.exists();
        if (!exists) {
            console.log('スケジュール設定が存在しません。デフォルト設定を使用します。');
            return {
                version: 1,
                updatedAt: new Date().toISOString(),
                schedules: DEFAULT_SCHEDULES,
                history: [],
            };
        }
        
        const [content] = await file.download();
        const config = JSON.parse(content.toString());
        console.log(`スケジュール設定を読み込みました: ${config.schedules.length}件`);
        return config;
    } catch (error) {
        console.error('スケジュール設定の読み込みに失敗しました:', error.message);
        // エラー時はデフォルト設定を返す
        return {
            version: 1,
            updatedAt: new Date().toISOString(),
            schedules: DEFAULT_SCHEDULES,
            history: [],
        };
    }
};

/**
 * GCSに設定を保存
 * @param {object} config - スケジュール設定
 * @returns {Promise<void>}
 */
export const saveConfig = async (config) => {
    try {
        const bucket = storage.bucket(BUCKET_NAME);
        const file = bucket.file(CONFIG_PATH);
        
        // 履歴を制限
        if (config.history && config.history.length > MAX_HISTORY) {
            config.history = config.history.slice(-MAX_HISTORY);
        }
        
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
 * スケジュールを更新
 * @param {string} scheduleId - スケジュールID
 * @param {object} updates - 更新内容
 * @returns {Promise<object>} 更新後の設定
 */
export const updateSchedule = async (scheduleId, updates) => {
    const config = await loadConfig();
    const scheduleIndex = config.schedules.findIndex(s => s.id === scheduleId);
    
    if (scheduleIndex === -1) {
        throw new Error(`スケジュールが見つかりません: ${scheduleId}`);
    }
    
    config.schedules[scheduleIndex] = {
        ...config.schedules[scheduleIndex],
        ...updates,
    };
    
    await saveConfig(config);
    return config;
};

/**
 * 実行履歴を追加
 * @param {object} historyEntry - 履歴エントリ
 * @returns {Promise<void>}
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
 * @param {number} limit - 取得件数
 * @returns {Promise<Array>} 履歴一覧（新しい順）
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
    updateSchedule,
    addHistory,
    getHistory,
    DEFAULT_SCHEDULES,
};
