/**
 * データマート更新実行モジュール
 * 
 * BigQueryのスケジュールクエリと同等の処理をNode.jsから実行する
 * 
 * 設計:
 *   - BigQuery に run_time（タイムスタンプ）を渡す
 *   - BigQuery 側で DATE(@run_time, 'Asia/Tokyo') - 1日 = target_date を計算
 *   - タイムスタンプはタイムゾーン情報を含むので、環境に依存しない
 */

import bigquery from '../../db/bigquery/init.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { DATAMART } from '../../config/constants.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * target_date から run_time を計算（バックフィル用）
 * 
 * BigQuery クエリは DATE(@run_time, 'Asia/Tokyo') - 1日 で target_date を計算するため、
 * 指定した target_date になるように run_time を逆算する。
 * 
 * 計算: target_date の翌日の JST 00:00 に相当する UTC を返す
 * 
 * @param {string} targetDate - 集計対象の日付（YYYY-MM-DD形式）
 * @returns {string} run_time（ISO8601形式）
 * 
 * @example
 * targetDateToRunTime('2026-01-09')
 * // → '2026-01-09T15:00:00.000Z' (= JST 2026-01-10 00:00)
 * // BigQuery: DATE(@run_time, 'Asia/Tokyo') = '2026-01-10'
 * // BigQuery: target_date = '2026-01-10' - 1日 = '2026-01-09'
 */
export const targetDateToRunTime = (targetDate) => {
    // target_date の翌日の JST 00:00 を計算
    // targetDate = '2026-01-09' の場合:
    //   翌日 = '2026-01-10'
    //   JST '2026-01-10 00:00' = UTC '2026-01-09T15:00:00Z'
    
    const [year, month, day] = targetDate.split('-').map(Number);
    
    // 翌日の JST 00:00 を UTC に変換
    // JST = UTC + 9時間 なので、JST 00:00 = UTC 前日の 15:00
    const nextDayJstMidnightUtc = new Date(Date.UTC(year, month - 1, day + 1, -9, 0, 0));
    
    return nextDayJstMidnightUtc.toISOString();
};

/**
 * データマート（machine_stats）を更新
 * 
 * @param {string|null} runTime - 実行時刻（ISO8601形式）。省略時は現在時刻を使用
 *   - null: 現在時刻を使用 → target_date = 前日（JST基準）
 *   - ISO8601文字列: 指定した時刻を使用 → target_date = DATE(@run_time, 'Asia/Tokyo') - 1日
 * @returns {Promise<object>} 実行結果
 * 
 * @example
 * // 現在時刻で実行（target_date = 前日）
 * await runDatamartUpdate();
 * 
 * // バックフィル（target_date = '2026-01-09' にしたい場合）
 * const runTime = targetDateToRunTime('2026-01-09');
 * await runDatamartUpdate(runTime);
 */
export const runDatamartUpdate = async (runTime = null) => {
    console.log('データマート更新を開始します...');
    
    try {
        // SQLファイルを読み込み
        const sqlPath = path.join(__dirname, '../../../sql/datamart/machine_stats/query.sql');
        let sql = fs.readFileSync(sqlPath, 'utf8');
        
        // run_time を決定（null の場合は現在時刻）
        const effectiveRunTime = runTime || new Date().toISOString();
        
        // target_date を計算（ログ出力用）
        // BigQuery と同じロジック: DATE(@run_time, 'Asia/Tokyo') - 1日
        const runTimeDate = new Date(effectiveRunTime);
        const jstDate = new Date(runTimeDate.getTime() + 9 * 60 * 60 * 1000);
        const jstDateStr = jstDate.toISOString().split('T')[0];
        const targetDateForLog = new Date(jstDateStr + 'T00:00:00Z');
        targetDateForLog.setUTCDate(targetDateForLog.getUTCDate() - 1);
        const targetDate = targetDateForLog.toISOString().split('T')[0];
        
        // BigQueryのパラメータとして渡す
        const options = {
            query: sql,
            params: {
                run_time: bigquery.timestamp(effectiveRunTime),
            },
            location: 'US',
        };
        
        console.log(`  実行時刻(run_time): ${effectiveRunTime}`);
        console.log(`  対象日付(target_date): ${targetDate}`);
        
        // クエリ実行
        const [job] = await bigquery.createQueryJob(options);
        console.log(`  ジョブID: ${job.id}`);
        
        // 結果を待機
        await job.getQueryResults();
        
        // DML統計情報を取得
        const [metadata] = await job.getMetadata();
        // dmlStatsは statistics.query.dmlStats にある場合がある
        const dmlStats = metadata.statistics?.dmlStats || metadata.statistics?.query?.dmlStats || {};
        const insertedCount = parseInt(dmlStats.insertedRowCount || 0);
        const updatedCount = parseInt(dmlStats.updatedRowCount || 0);
        const deletedCount = parseInt(dmlStats.deletedRowCount || 0);
        const totalCount = insertedCount + updatedCount + deletedCount;
        
        // デバッグ: 統計情報の構造を確認
        if (totalCount === 0 && metadata.statistics) {
            console.log('  [DEBUG] statistics:', JSON.stringify(metadata.statistics, null, 2));
        }
        
        console.log(`データマート更新完了`);
        console.log(`  処理件数: ${totalCount}件 (挿入: ${insertedCount}, 更新: ${updatedCount}, 削除: ${deletedCount})`);
        
        return {
            success: true,
            jobId: job.id,
            runTime: effectiveRunTime,
            targetDate,
            dmlStats: { inserted: insertedCount, updated: updatedCount, deleted: deletedCount, total: totalCount },
        };
    } catch (error) {
        console.error('データマート更新中にエラーが発生しました:', error.message);
        
        // BigQueryエラーの詳細情報を出力
        logBigQueryErrorDetails(error);
        
        throw error;
    }
};

/**
 * BigQueryエラーの詳細情報をログ出力
 * 
 * @param {Error} error - エラーオブジェクト
 */
const logBigQueryErrorDetails = (error) => {
    // BigQueryのレート制限に関する情報
    const rateLimitInfo = {
        rateLimitExceeded: {
            description: '一般的なレート制限超過',
            limit: '詳細はBigQueryダッシュボードで確認',
            suggestion: '並列数を下げるか、時間を空けて再実行',
        },
        quotaExceeded: {
            description: 'クォータ超過',
            limit: '詳細はBigQueryダッシュボードで確認',
            suggestion: 'クォータ上限の引き上げをリクエスト',
        },
        // DML関連のレート制限
        'too many table dml insert operations': {
            description: 'テーブルDML操作数の上限超過',
            limit: '1テーブルあたり1,500 DML/日、10 DML/秒',
            suggestion: '並列数を下げる、バッチサイズを大きくする、時間を空ける',
        },
        'too many concurrent dml': {
            description: '同時DML操作数の上限超過',
            limit: '1テーブルあたり20同時DML（ストリーミングバッファあり時は3）',
            suggestion: '並列数を下げる',
        },
    };
    
    // エラーメッセージから該当する制限を特定
    const errorMsg = error.message?.toLowerCase() || '';
    let matchedLimit = null;
    
    for (const [key, info] of Object.entries(rateLimitInfo)) {
        if (errorMsg.includes(key.toLowerCase())) {
            matchedLimit = { key, ...info };
            break;
        }
    }
    
    // BigQueryエラーオブジェクトの詳細を出力
    console.error('  ===== BigQuery エラー詳細 =====');
    
    if (error.code) {
        console.error(`  HTTPコード: ${error.code}`);
    }
    
    // errors配列がある場合（BigQuery APIエラー）
    if (error.errors && Array.isArray(error.errors)) {
        for (const e of error.errors) {
            console.error(`  reason: ${e.reason || 'unknown'}`);
            console.error(`  location: ${e.location || 'unknown'}`);
            console.error(`  message: ${e.message || 'unknown'}`);
        }
    }
    
    // 該当する制限情報があれば出力
    if (matchedLimit) {
        console.error('  ----- 制限情報 -----');
        console.error(`  種類: ${matchedLimit.description}`);
        console.error(`  制限値: ${matchedLimit.limit}`);
        console.error(`  対処法: ${matchedLimit.suggestion}`);
    }
    
    // リトライ可能かどうかの判定
    const isRetryable = errorMsg.includes('rate limit') || 
                        errorMsg.includes('quota') ||
                        errorMsg.includes('too many') ||
                        error.code === 429 ||
                        error.code === 503;
    
    console.error(`  リトライ可能: ${isRetryable ? 'はい（自動リトライ対象）' : 'いいえ'}`);
    console.error('  参考: https://cloud.google.com/bigquery/quotas');
    console.error('  ================================');
};

/**
 * 指定ミリ秒待機するユーティリティ
 * 
 * @param {number} ms - 待機ミリ秒
 * @returns {Promise<void>}
 */
const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

/**
 * 並列度を制限しながらPromiseを実行するユーティリティ
 * タスク開始間隔を設定することで、秒間リクエスト数を制御可能
 * 
 * @param {Array<{task: () => Promise, index: number}>} taskItems - 実行するタスクと元のインデックス
 * @param {number} concurrency - 同時実行数
 * @param {number} intervalMs - タスク開始間隔（ミリ秒）。0の場合は間隔なし
 * @returns {Promise<Array<{index: number, result: any}>>} 実行結果の配列
 */
const runWithConcurrency = async (taskItems, concurrency, intervalMs = 0) => {
    const results = [];
    let currentIndex = 0;
    let lastStartTime = 0;
    let lockPromise = Promise.resolve();
    
    const runNext = async () => {
        while (currentIndex < taskItems.length) {
            // インターバル制御（排他的にアクセス）
            if (intervalMs > 0) {
                // 前の待機が完了するまで待つ
                await lockPromise;
                
                // 新しい待機処理を設定
                let releaseLock;
                lockPromise = new Promise(resolve => { releaseLock = resolve; });
                
                // 必要な待機時間を計算
                const now = Date.now();
                const waitTime = Math.max(0, lastStartTime + intervalMs - now);
                if (waitTime > 0) {
                    await sleep(waitTime);
                }
                lastStartTime = Date.now();
                
                // ロックを解放（次のワーカーが進める）
                releaseLock();
            }
            
            const idx = currentIndex++;
            const { task, index } = taskItems[idx];
            try {
                const result = await task();
                results.push({ index, result });
            } catch (error) {
                results.push({ index, result: { success: false, error: error.message } });
            }
        }
    };
    
    // concurrency 個のワーカーを起動
    const workers = Array(Math.min(concurrency, taskItems.length))
        .fill(null)
        .map(() => runNext());
    
    await Promise.all(workers);
    return results;
};

/**
 * 特定の日付範囲でデータマートを再構築（バックフィル）
 * 
 * 指定した日付範囲の各日付に対してデータマート更新を実行する。
 * startDate, endDate はそのまま target_date として扱われる。
 * 失敗した日付は自動的にリトライされる（並列実行）。
 * 
 * @param {string} startDate - 開始日（YYYY-MM-DD）= 最初の target_date
 * @param {string} endDate - 終了日（YYYY-MM-DD）= 最後の target_date
 * @param {object} options - オプション
 * @param {number} options.concurrency - 同時実行数（デフォルト: 設定値）
 * @returns {Promise<object[]>} 実行結果の配列
 * 
 * @example
 * // 2026-01-07 〜 2026-01-09 のデータマートを再構築
 * await rebuildDatamart('2026-01-07', '2026-01-09');
 * 
 * // 10並列で実行
 * await rebuildDatamart('2026-01-01', '2026-01-31', { concurrency: 10 });
 */
export const rebuildDatamart = async (startDate, endDate, options = {}) => {
    const { concurrency = DATAMART.concurrency.default } = options;
    const { maxAttempts, delayMs } = DATAMART.retry;
    const { intervalMs } = DATAMART;
    
    console.log(`データマート再構築を開始します: ${startDate} 〜 ${endDate}`);
    console.log(`  設定: 並列数=${concurrency}, 開始間隔=${intervalMs}ms, 最大リトライ=${maxAttempts}回`);
    
    // 日付範囲を生成（JST明示で環境非依存）
    const dates = [];
    const start = new Date(startDate + 'T00:00:00+09:00');
    const end = new Date(endDate + 'T00:00:00+09:00');
    const current = new Date(start);
    
    while (current <= end) {
        dates.push(current.toISOString().split('T')[0]);
        current.setDate(current.getDate() + 1);
    }
    
    console.log(`  対象日数: ${dates.length}日`);
    
    // 結果配列を初期化
    const results = new Array(dates.length).fill(null);
    
    // 処理対象のインデックスリスト（最初は全日付）
    let pendingIndices = dates.map((_, i) => i);
    
    // リトライループ
    for (let attempt = 1; attempt <= maxAttempts && pendingIndices.length > 0; attempt++) {
        if (attempt > 1) {
            console.log(`  リトライ ${attempt}/${maxAttempts} (失敗: ${pendingIndices.length}件, ${delayMs}ms後に再実行)`);
            await sleep(delayMs);
        }
        
        // タスクを生成
        const taskItems = pendingIndices.map(index => ({
            index,
            task: async () => {
                const dateStr = dates[index];
                const runTime = targetDateToRunTime(dateStr);
                const result = await runDatamartUpdate(runTime);
                return { date: dateStr, ...result };
            }
        }));
        
        // 並列実行（開始間隔制御付き）
        const batchResults = await runWithConcurrency(taskItems, concurrency, intervalMs);
        
        // 結果を反映し、失敗したインデックスを収集
        const failedIndices = [];
        for (const { index, result } of batchResults) {
            results[index] = result;
            if (!result.success) {
                failedIndices.push(index);
            }
        }
        
        // 次のリトライ対象を更新
        pendingIndices = failedIndices;
        
        const successCount = batchResults.filter(r => r.result.success).length;
        const failCount = failedIndices.length;
        console.log(`  試行 ${attempt}: 成功=${successCount}, 失敗=${failCount}`);
    }
    
    const finalSuccessCount = results.filter(r => r && r.success).length;
    const finalFailCount = results.filter(r => r && !r.success).length;
    
    console.log(`データマート再構築完了: 成功=${finalSuccessCount}, 失敗=${finalFailCount}`);
    
    return results;
};

export default {
    runDatamartUpdate,
    rebuildDatamart,
    targetDateToRunTime,
};
