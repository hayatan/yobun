/**
 * データマート更新実行モジュール
 * 
 * BigQueryのスケジュールクエリと同等の処理をNode.jsから実行する
 */

import bigquery from '../../db/bigquery/init.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { addDays } from 'date-fns';
import { zonedTimeToUtc } from 'date-fns-tz';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * データマート（machine_stats）を更新
 * @param {string} targetDate - 対象日付（YYYY-MM-DD形式）。省略時は実行時刻から自動計算
 * @returns {Promise<object>} 実行結果
 */
export const runDatamartUpdate = async (targetDate = null) => {
    console.log('データマート更新を開始します...');
    
    try {
        // SQLファイルを読み込み
        const sqlPath = path.join(__dirname, '../../../sql/datamart/machine_stats/query.sql');
        let sql = fs.readFileSync(sqlPath, 'utf8');
        
        // @run_time パラメータを計算
        // targetDate が指定されている場合は、その翌日のJST 0時をUTCに変換してrun_timeとする
        // （query.sqlでは DATE(@run_time, 'Asia/Tokyo') - 1日 = target_date として計算されるため）
        let runTime;
        if (targetDate) {
            // targetDate (JST) の翌日の JST 0時を計算
            const nextDayJst = addDays(new Date(targetDate + 'T00:00:00'), 1);
            const nextDayJstString = nextDayJst.toISOString().split('T')[0];
            const jstMidnight = `${nextDayJstString}T00:00:00`;
            
            // JST の日時を UTC に変換
            const utcTime = zonedTimeToUtc(jstMidnight, 'Asia/Tokyo');
            runTime = utcTime.toISOString();
        } else {
            runTime = new Date().toISOString();
        }
        
        // BigQueryのパラメータとして渡す
        const options = {
            query: sql,
            params: {
                run_time: bigquery.timestamp(runTime),
            },
            location: 'US',
        };
        
        console.log(`  実行時刻(run_time): ${runTime}`);
        console.log(`  対象日付(target_date): ${targetDate || '実行日の前日（自動計算）'}`);
        
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
            runTime,
            targetDate,
            rowCount: rows.length,
        };
    } catch (error) {
        console.error('データマート更新中にエラーが発生しました:', error.message);
        throw error;
    }
};

/**
 * 特定の日付範囲でデータマートを再構築
 * （通常は使用しない。データ修正時などに使用）
 * @param {string} startDate - 開始日（YYYY-MM-DD）
 * @param {string} endDate - 終了日（YYYY-MM-DD）
 * @returns {Promise<object>} 実行結果
 */
export const rebuildDatamart = async (startDate, endDate) => {
    console.log(`データマート再構築を開始します: ${startDate} 〜 ${endDate}`);
    
    // 各日付に対してデータマート更新を実行
    const results = [];
    
    // 日付範囲を生成（タイムゾーン非依存）
    const start = new Date(startDate + 'T00:00:00');
    const end = new Date(endDate + 'T00:00:00');
    const current = new Date(start);
    
    while (current <= end) {
        const dateStr = current.toISOString().split('T')[0];
        try {
            // runDatamartUpdateに日付を渡す（内部でJST考慮してrun_timeに変換される）
            const result = await runDatamartUpdate(dateStr);
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
};
