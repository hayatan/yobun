import scrape from './services/slorepo/index.js';

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
