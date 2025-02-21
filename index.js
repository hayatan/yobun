require('dotenv').config();
const { bigquery } = require('./bigquery');
const { db } = require('./sqlite');
const { runScrape } = require('./src/app');

// メイン処理
(async () => {
    try {
        console.log(process.env.NODE_ENV, bigquery, db);
        await runScrape(bigquery, db, new Date().setDate(new Date().getDate() - 100));
    } catch (error) {
        console.error('スクレイピング処理中にエラーが発生しました:', error);
    }
})();
