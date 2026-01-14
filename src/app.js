import scrape from './services/slorepo/index.js';
import { BIGQUERY, DEFAULT_SCRAPE_DAYS } from './config/constants.js';

/**
 * スクレイピング実行処理
 * @param {Object} bigquery - BigQueryクライアント
 * @param {Object} db - SQLiteデータベース
 * @param {Function} updateProgress - 進捗更新コールバック
 * @param {Object} params - パラメータ
 * @param {string} params.startDate - 開始日
 * @param {string} params.endDate - 終了日
 * @param {boolean} params.continueOnError - エラー時も処理を継続する（デフォルト: true）
 * @param {boolean} params.force - 既存データを無視して再取得する（デフォルト: false）
 * @param {boolean} params.prioritizeHigh - 高優先度店舗を先に処理する（デフォルト: false）
 * @returns {Promise<Object>} スクレイピング結果
 */
export const runScrape = async (bigquery, db, updateProgress, { 
    startDate, 
    endDate,
    continueOnError = true,
    force = false,
    prioritizeHigh = false,
} = {}) => {
    const { datasetId, tableIdPrefix } = BIGQUERY;

    // 日付が指定されていない場合はデフォルト値を使用
    const start = startDate ? new Date(startDate) : new Date().setDate(new Date().getDate() - DEFAULT_SCRAPE_DAYS);
    const end = endDate ? new Date(endDate) : new Date();

    const options = {
        continueOnError,
        force,
        prioritizeHigh,
    };

    console.log('スクレイピング処理を開始します...');
    const result = await scrape(bigquery, datasetId, tableIdPrefix, db, start, end, updateProgress, options);
    console.log('スクレイピング処理が完了しました。');
    
    return result;
};
