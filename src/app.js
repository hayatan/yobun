import scrape from './scrape.js';
import util from './util/common.js';
import sqlite from './db/sqlite/operations.js';
import slorepo from './slorepo.js';
import config from './slorepo-config.js';
import { getBigQueryRowCount, saveToBigQueryReplace } from './db/bigquery/operations.js';

// スクレイピング実行処理
export const runScrape = async (bigquery, db, updateProgress) => {
    const datasetId = 'slot_data';
    const tableIdPrefix = 'data_';

    const startDate = new Date().setDate(new Date().getDate() - 3);
    const endDate = new Date();

    console.log('スクレイピング処理を開始します...');
    await scrape(bigquery, datasetId, tableIdPrefix, db, startDate, endDate, updateProgress);
    console.log('スクレイピング処理が完了しました。');
};
