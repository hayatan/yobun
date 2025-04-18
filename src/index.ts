import 'dotenv/config';
import bigquery from './db/bigquery/init.js';
import db from './db/sqlite/init.js';
import { runScrape } from './app.ts';
import util from './util/common.js';

// メイン処理
(async (): Promise<void> => {
    try {
        console.log(process.env.NODE_ENV, bigquery, db);
        const { startDate, endDate } = util.getDefaultDateRange();
        await runScrape(bigquery, db, startDate, endDate);
    } catch (error) {
        console.error('スクレイピング処理中にエラーが発生しました:', error);
    }
})(); 