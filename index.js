import 'dotenv/config';
import bigquery from './src/db/bigquery/init.js';
import db from './src/db/sqlite/init.js';
import { runScrape } from './src/app.js';

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
