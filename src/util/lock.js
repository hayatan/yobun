/**
 * GCSベースのロック機構
 * 
 * ローカルDocker実行とCloud Run Jobs実行で同じGCSバケットを共有し、
 * SQLite + Litestreamの同時書き込みを防止する
 */

import { Storage } from '@google-cloud/storage';

const storage = new Storage();
const LOCK_BUCKET = 'youbun-sqlite';
const LOCK_FILE = 'job.lock';
const LOCK_TIMEOUT_MS = 6 * 60 * 60 * 1000; // 6時間

/**
 * ロックを取得
 * @returns {Promise<boolean>} ロック取得成功時true、既にロック中の場合false
 */
export const acquireLock = async () => {
    try {
        const bucket = storage.bucket(LOCK_BUCKET);
        const file = bucket.file(LOCK_FILE);
        
        const [exists] = await file.exists();
        if (exists) {
            const [content] = await file.download();
            const lockData = JSON.parse(content.toString());
            const lockAge = Date.now() - new Date(lockData.startedAt).getTime();
            
            if (lockAge < LOCK_TIMEOUT_MS) {
                const hours = Math.floor(lockAge / 3600000);
                const mins = Math.floor((lockAge % 3600000) / 60000);
                console.log(`ロック中: ${lockData.environment} で実行中（${hours}時間${mins}分経過）`);
                console.log(`  開始時刻: ${lockData.startedAt}`);
                console.log(`  実行モード: ${lockData.jobMode}`);
                return false;
            }
            
            console.warn(`ロックタイムアウト（6時間超過）。強制的に上書きします。`);
            console.warn(`  古いロック情報: ${JSON.stringify(lockData)}`);
        }
        
        const lockData = {
            startedAt: new Date().toISOString(),
            environment: process.env.NODE_ENV === 'production' ? 'Cloud Run' : 'Local Docker',
            jobMode: process.env.JOB_MODE || 'manual',
        };
        
        await file.save(JSON.stringify(lockData, null, 2));
        console.log('ロックを取得しました');
        console.log(`  環境: ${lockData.environment}`);
        console.log(`  モード: ${lockData.jobMode}`);
        return true;
    } catch (error) {
        console.error('ロック取得中にエラーが発生しました:', error.message);
        // エラー時はロック取得失敗として扱う（安全側に倒す）
        return false;
    }
};

/**
 * ロックを解放
 * @returns {Promise<void>}
 */
export const releaseLock = async () => {
    try {
        const bucket = storage.bucket(LOCK_BUCKET);
        await bucket.file(LOCK_FILE).delete({ ignoreNotFound: true });
        console.log('ロックを解放しました');
    } catch (error) {
        console.error('ロック解放中にエラーが発生しました:', error.message);
        // 解放失敗はログに残すが、処理は継続
    }
};

/**
 * 現在のロック状態を取得
 * @returns {Promise<object|null>} ロック情報、またはロックがない場合null
 */
export const getLockStatus = async () => {
    try {
        const bucket = storage.bucket(LOCK_BUCKET);
        const file = bucket.file(LOCK_FILE);
        
        const [exists] = await file.exists();
        if (!exists) {
            return null;
        }
        
        const [content] = await file.download();
        const lockData = JSON.parse(content.toString());
        const lockAge = Date.now() - new Date(lockData.startedAt).getTime();
        
        return {
            ...lockData,
            ageMs: lockAge,
            ageHours: Math.floor(lockAge / 3600000),
            ageMinutes: Math.floor((lockAge % 3600000) / 60000),
            isExpired: lockAge >= LOCK_TIMEOUT_MS,
        };
    } catch (error) {
        console.error('ロック状態取得中にエラーが発生しました:', error.message);
        return null;
    }
};

/**
 * ロック付きでタスクを実行
 * @param {Function} task - 実行するタスク関数
 * @returns {Promise<object>} タスクの結果、またはスキップ情報
 */
export const runWithLock = async (task) => {
    if (!await acquireLock()) {
        console.log('別の処理が実行中のためスキップします');
        return { skipped: true, reason: 'locked' };
    }
    
    try {
        const result = await task();
        return { skipped: false, result };
    } finally {
        await releaseLock();
    }
};

export default {
    acquireLock,
    releaseLock,
    getLockStatus,
    runWithLock,
    LOCK_TIMEOUT_MS,
};
