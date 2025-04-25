import scrape from './services/slorepo/index.js';

// スクレイピング実行処理
export const runScrape = async (bigquery, db, updateProgress, { startDate, endDate } = {}) => {
    const datasetId = 'slot_data';
    const tableIdPrefix = 'data_';

    // 日付が指定されていない場合はデフォルト値を使用
    const start = startDate ? new Date(startDate) : new Date().setDate(new Date().getDate() - 3);
    const end = endDate ? new Date(endDate) : new Date();

    console.log('スクレイピング処理を開始します...');
    await scrape(bigquery, datasetId, tableIdPrefix, db, start, end, updateProgress);
    console.log('スクレイピング処理が完了しました。');
};
