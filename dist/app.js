import scrape from './services/slorepo';
// スクレイピング実行処理
export const runScrape = async (bigquery, db, updateProgress) => {
    const datasetId = 'slot_data';
    const tableIdPrefix = 'data_';
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - 3);
    const endDate = new Date();
    console.log('スクレイピング処理を開始します...');
    await scrape(bigquery, datasetId, tableIdPrefix, db, startDate, endDate, updateProgress);
    console.log('スクレイピング処理が完了しました。');
};
