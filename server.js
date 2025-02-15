require('dotenv').config();
const sqlite3 = require('sqlite3').verbose();
const { BigQuery } = require('@google-cloud/bigquery');
const { execSync } = require('child_process');

const scrape = require('./src/scrape');

// SQLiteデータベース
const dbPath = './data/local_db.sqlite';
const db = new sqlite3.Database(dbPath, (err) => {
    if (err) {
        console.error('SQLiteデータベース接続エラー:', err);
    } else {
        console.log('SQLiteデータベースに接続しました:', dbPath);
    }
});

// 環境によって認証情報を切り替える
const bigquery =
    process.env.NODE_ENV === 'production'
        ? new BigQuery() // 本番環境ではデフォルト認証を利用
        : new BigQuery({
            projectId: 'yobun-450512',
              keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS,
          }); // 開発環境ではキーを直接

// メイン処理
(async () => {
    const datasetId = 'slot_data';
    const tableIdPrefix = 'data_';

    // SQLiteの復元（コンテナ起動時）
    try {
        console.log('GCSバックアップからSQLiteを復元中...');
        execSync(`litestream restore -o ${dbPath} youbun-sqlite/sqlite-backup`);
        await createoSQLiteTableIfNotExists(db);
    } catch (err) {
        console.log('復元失敗。新しいデータベースを使用します。');
    }

    const startDate = new Date();
    startDate.setDate(startDate.getDate() - 3); // 現在日時の3日前を設定
    const endDate = new Date();
    
    await scrape(bigquery, datasetId, tableIdPrefix, db, startDate, endDate);
})();
