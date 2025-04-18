import 'dotenv/config';
import scrapeSlorepo from './services/slorepo/index.js';
import { BigQuery } from '@google-cloud/bigquery';
import sqlite3 from 'sqlite3';
const { Database } = sqlite3;

type UpdateProgressCallback = (completed: number, total: number, message: string) => void;

// スクレイピング実行処理
export const runScrape = async (
    bigquery: BigQuery,
    db: InstanceType<typeof Database>,
    updateProgress: UpdateProgressCallback
): Promise<void> => {
    const datasetId = 'slot_data';
    const tableIdPrefix = 'data_';

    const startDate = new Date();
    startDate.setDate(startDate.getDate() - 3);
    const endDate = new Date();

    console.log('スクレイピング処理を開始します...');
    await scrapeSlorepo(bigquery, datasetId, tableIdPrefix, db, startDate, endDate, updateProgress);
    console.log('スクレイピング処理が完了しました。');
}; 