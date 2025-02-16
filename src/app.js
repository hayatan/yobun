const sqlite3 = require('sqlite3').verbose();
const { BigQuery } = require('@google-cloud/bigquery');
const { execSync } = require('child_process');
const scrape = require('./scrape');
const util = require('./util/common');

// SQLiteデータベースの設定
const dbPath = './data/local_db.sqlite';
const db = new sqlite3.Database(dbPath, (err) => {
    if (err) {
        console.error('SQLiteデータベース接続エラー:', err);
    } else {
        console.log('SQLiteデータベースに接続しました:', dbPath);
    }
});

// 環境に応じたBigQueryの設定
const bigquery =
    process.env.NODE_ENV === 'production'
        ? new BigQuery() // 本番環境ではデフォルト認証を利用
        : new BigQuery({
            projectId: 'yobun-450512',
            keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS,
        }); // 開発環境ではキーを直接

// SQLiteの復元処理
const restoreSQLite = async () => {
    try {
        console.log('GCSバックアップからSQLiteを復元中...');
        execSync(`litestream restore -o ${dbPath} youbun-sqlite/sqlite-backup`);
        console.log('SQLiteデータベースを復元しました。');
    } catch (err) {
        console.log('復元失敗。新しいデータベースを使用します。');
    }
};

// スクレイピング実行処理
const runScrape = async () => {
    const datasetId = 'slot_data';
    const tableIdPrefix = 'data_';

    const startDate = new Date();
    startDate.setDate(startDate.getDate() - 3); // 現在日時の3日前を設定
    const endDate = new Date();

    console.log('スクレイピング処理を開始します...');
    await scrape(bigquery, datasetId, tableIdPrefix, db, startDate, endDate);
    console.log('スクレイピング処理が完了しました。');
};

module.exports = {
    restoreSQLite,
    runScrape,
};
