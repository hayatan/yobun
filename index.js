require('dotenv').config();
const bigquery = require('./src/db/bigquery/init');
const db = require('./src/db/sqlite/init');
const { runScrape } = require('./src/app');

// メイン処理
(async () => {
    try {
        console.log(process.env.NODE_ENV, bigquery, db);
        const startDate = new Date().setDate(new Date().getDate() - 7);
        await runScrape(bigquery, db, startDate);
    } catch (error) {
        console.error('スクレイピング処理中にエラーが発生しました:', error);
    }
})();
