/**
 * Cloud Run Jobs用エントリポイント
 * 
 * スクレイピングとデータマート更新を実行する
 * 
 * 環境変数:
 *   JOB_MODE: 実行モード
 *     - priority: 優先店舗（priority: high）のみ処理
 *     - normal: 全店舗を対象に未取得分を処理
 *     - all: 全店舗処理（ローカルテスト用）
 */

import 'dotenv/config';
import { getJSTYesterday, getJSTTimeString } from './src/util/date.js';
import { acquireLock, releaseLock } from './src/util/lock.js';
import { runScrape } from './src/app.js';
import { runDatamartUpdate } from './src/services/datamart/runner.js';
import bigquery from './src/db/bigquery/init.js';
import db from './src/db/sqlite/init.js';

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
        // モードに応じたオプションを設定
        const options = {
            startDate: targetDate,
            endDate: targetDate,
            continueOnError: true,
            force: false,
            priorityFilter: mode === 'priority' ? 'high' : null,
        };
        
        console.log(`スクレイピングを開始します (priorityFilter=${options.priorityFilter})`);
        
        // runScrape を使用してスクレイピング実行
        const result = await runScrape(bigquery, db, null, options);
        
        // 結果サマリ
        console.log('');
        console.log('='.repeat(60));
        console.log('スクレイピング結果');
        console.log('='.repeat(60));
        console.log(`  成功: ${result.success.length}件`);
        console.log(`  スキップ: ${result.skipped.length}件`);
        console.log(`  失敗: ${result.failed.length}件`);
        
        if (result.failed.length > 0) {
            console.log('');
            console.log('失敗した店舗:');
            result.failed.forEach(f => console.log(`  - ${f.date}_${f.hole}: ${f.error}`));
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
        if (result.failed.length > 0 && result.success.length === 0) {
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
