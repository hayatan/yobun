import scrape from './scrape.js';

// スクレイピング実行処理
export const runScrape = async (bigquery, db, startDate) => {
    const datasetId = 'slot_data';
    const tableIdPrefix = 'data_';

    startDate = startDate ? new Date(startDate) : new Date().setDate(new Date().getDate() - 3);
    const endDate = new Date();

    console.log('スクレイピング処理を開始します...');
    await scrape(bigquery, datasetId, tableIdPrefix, db, startDate, endDate);
    console.log('スクレイピング処理が完了しました。');
};
