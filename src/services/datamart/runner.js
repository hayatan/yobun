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
        const [rows] = await job.getQueryResults();
        
        console.log(`データマート更新完了`);
        console.log(`  処理件数: ${rows.length || 'MERGE実行（件数不明）'}`);
        
        return {
            success: true,
            jobId: job.id,
            runTime: effectiveRunTime,
            targetDate,
            rowCount: rows.length,
        };
    } catch (error) {
        console.error('データマート更新中にエラーが発生しました:', error.message);
        throw error;
    }
};

/**
 * 特定の日付範囲でデータマートを再構築（バックフィル）
 * 
 * 指定した日付範囲の各日付に対してデータマート更新を実行する。
 * startDate, endDate はそのまま target_date として扱われる。
 * 
 * @param {string} startDate - 開始日（YYYY-MM-DD）= 最初の target_date
 * @param {string} endDate - 終了日（YYYY-MM-DD）= 最後の target_date
 * @returns {Promise<object[]>} 実行結果の配列
 * 
 * @example
 * // 2026-01-07 〜 2026-01-09 のデータマートを再構築
 * await rebuildDatamart('2026-01-07', '2026-01-09');
 * // → target_date = '2026-01-07', '2026-01-08', '2026-01-09' の3日分を実行
 */
export const rebuildDatamart = async (startDate, endDate) => {
    console.log(`データマート再構築を開始します: ${startDate} 〜 ${endDate}`);
    
    // 各日付に対してデータマート更新を実行
    const results = [];
    
    // 日付範囲を生成（JST明示で環境非依存）
    const start = new Date(startDate + 'T00:00:00+09:00');
    const end = new Date(endDate + 'T00:00:00+09:00');
    const current = new Date(start);
    
    while (current <= end) {
        const dateStr = current.toISOString().split('T')[0];
        try {
            // targetDate から run_time を計算して渡す
            const runTime = targetDateToRunTime(dateStr);
            const result = await runDatamartUpdate(runTime);
            results.push({ date: dateStr, ...result });
        } catch (error) {
            results.push({ date: dateStr, success: false, error: error.message });
        }
        
        current.setDate(current.getDate() + 1);
    }
    
    console.log(`データマート再構築完了: 成功=${results.filter(r => r.success).length}, 失敗=${results.filter(r => !r.success).length}`);
    
    return results;
};

export default {
    runDatamartUpdate,
    rebuildDatamart,
    targetDateToRunTime,
};
