/**
 * Cloud Run Jobs用エントリポイント
 * 
 * スクレイピングとデータマート更新を実行する
 * 
 * 環境変数:
 *   JOB_MODE: 実行モード
 *     - priority: 優先店舗（lateUpdate: true）のみ処理
 *     - normal: 全店舗を対象に未取得分を処理
 *     - all: 全店舗処理（ローカルテスト用）
 */

import 'dotenv/config';
import { getJSTYesterday, getJSTTimeString } from './src/util/date.js';
import { acquireLock, releaseLock } from './src/util/lock.js';
import { runDatamartUpdate } from './src/services/datamart/runner.js';
import scrapeSlotDataByMachine from './src/services/slorepo/scraper.js';
import { getHoles } from './src/config/slorepo-config.js';
import bigquery from './src/db/bigquery/init.js';
import db from './src/db/sqlite/init.js';
import sqlite from './src/db/sqlite/operations.js';
import { getTable, saveToBigQuery, getBigQueryRowCount } from './src/db/bigquery/operations.js';
import { BIGQUERY, SCRAPING } from './src/config/constants.js';
import util from './src/util/common.js';

const main = async () => {
    const mode = process.env.JOB_MODE || 'all';
    const targetDate = getJSTYesterday();
    
    console.log('='.repeat(60));
    console.log('Cloud Run Job 開始');
    console.log('='.repeat(60));
    console.log(`  実行時刻: ${new Date().toISOString()} (${getJSTTimeString()} JST)`);
    console.log(`  実行モード: ${mode}`);
    console.log(`  対象日付: ${targetDate}`);
    console.log('='.repeat(60));
    
    // ロック取得
    if (!await acquireLock(mode)) {
        console.log('別の処理が実行中のためスキップします');
        process.exit(0);
    }
    
    try {
        // 対象店舗を決定
        let holes;
        if (mode === 'priority') {
            // 優先店舗のみ（7:00-8:00の集中リトライ用）
            holes = getHoles({ lateUpdate: true, active: true });
            console.log(`優先店舗モード: ${holes.length}店舗を処理`);
        } else {
            // normal または all: 全店舗を対象
            holes = getHoles({ active: true });
            console.log(`全店舗モード: ${holes.length}店舗を処理`);
        }
        
        const results = {
            success: [],
            skipped: [],
            failed: [],
        };
        
        // BigQueryテーブルを取得/作成
        const { datasetId, tableIdPrefix } = BIGQUERY;
        const tableId = `${tableIdPrefix}${util.formatUrlDate(targetDate)}`;
        const table = await getTable(bigquery, datasetId, tableId);
        
        // 各店舗を処理
        for (const hole of holes) {
            const taskId = `${targetDate}_${hole.name}`;
            
            try {
                // データ存在確認
                const exists = await sqlite.isDiffDataExists(db, targetDate, hole.name);
                
                if (exists) {
                    console.log(`[${targetDate}][${hole.name}] データあり、スキップ`);
                    results.skipped.push(taskId);
                    continue;
                }
                
                console.log(`[${targetDate}][${hole.name}] データなし、スクレイピング開始`);
                
                // スクレイピング実行
                const data = await scrapeSlotDataByMachine(targetDate, hole.code, SCRAPING.intervalMs);
                
                if (data.length === 0) {
                    console.log(`[${targetDate}][${hole.name}] データが取得できませんでした`);
                    results.failed.push({ taskId, error: 'データなし' });
                    continue;
                }
                
                // SQLiteに保存
                await sqlite.saveDiffData(db, data);
                console.log(`[${targetDate}][${hole.name}] SQLiteに保存完了: ${data.length}件`);
                
                // BigQueryに保存
                const savedData = await sqlite.getDiffData(db, targetDate, hole.name);
                if (savedData.length > 0) {
                    await saveToBigQuery(table, savedData);
                    console.log(`[${targetDate}][${hole.name}] BigQueryに保存完了: ${savedData.length}件`);
                }
                
                results.success.push(taskId);
                
            } catch (error) {
                console.error(`[${targetDate}][${hole.name}] エラー: ${error.message}`);
                results.failed.push({ taskId, error: error.message });
            }
        }
        
        // 結果サマリ
        console.log('');
        console.log('='.repeat(60));
        console.log('スクレイピング結果');
        console.log('='.repeat(60));
        console.log(`  成功: ${results.success.length}件`);
        console.log(`  スキップ: ${results.skipped.length}件`);
        console.log(`  失敗: ${results.failed.length}件`);
        
        if (results.failed.length > 0) {
            console.log('');
            console.log('失敗した店舗:');
            results.failed.forEach(f => console.log(`  - ${f.taskId}: ${f.error}`));
        }
        
        // データマート更新
        console.log('');
        console.log('='.repeat(60));
        console.log('データマート更新');
        console.log('='.repeat(60));
        
        try {
            await runDatamartUpdate(targetDate);
            console.log('データマート更新完了');
        } catch (error) {
            console.error('データマート更新中にエラーが発生しました:', error.message);
            // データマート更新の失敗はジョブ全体の失敗とはしない
        }
        
        console.log('');
        console.log('='.repeat(60));
        console.log('Cloud Run Job 完了');
        console.log('='.repeat(60));
        
        // 失敗があった場合は終了コード1で終了（リトライのため）
        if (results.failed.length > 0 && results.success.length === 0) {
            process.exit(1);
        }
        
    } finally {
        await releaseLock();
    }
};

// エラーハンドリング
process.on('unhandledRejection', async (error) => {
    console.error('未処理のPromise拒否:', error);
    try {
        await releaseLock();
    } catch (e) {
        console.error('ロック解放中にエラー:', e.message);
    }
    process.exit(1);
});

process.on('SIGTERM', async () => {
    console.log('SIGTERMを受信しました。終了処理を開始します...');
    try {
        await releaseLock();
    } catch (e) {
        console.error('ロック解放中にエラー:', e.message);
    }
    process.exit(0);
});

// メイン処理実行
main().catch(async (error) => {
    console.error('メイン処理でエラーが発生しました:', error);
    try {
        await releaseLock();
    } catch (e) {
        console.error('ロック解放中にエラー:', e.message);
    }
    process.exit(1);
});
