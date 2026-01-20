import scrape from './services/slorepo/index.js';
import { BIGQUERY, DEFAULT_SCRAPE_DAYS } from './config/constants.js';
import { getJSTDate, generateDateRange } from './util/date.js';

/**
 * スクレイピング実行処理
 * @param {Object} bigquery - BigQueryクライアント
 * @param {Object} db - SQLiteデータベース
 * @param {Function} updateProgress - 進捗更新コールバック
 * @param {Object} params - パラメータ
 * @param {string} params.startDate - 開始日（YYYY-MM-DD形式）
 * @param {string} params.endDate - 終了日（YYYY-MM-DD形式）
 * @param {boolean} params.continueOnError - エラー時も処理を継続する（デフォルト: true）
 * @param {boolean} params.force - 既存データを無視して再取得する（デフォルト: false）
 * @param {string|null} params.priorityFilter - 対象店舗の優先度フィルター（'high', 'normal', 'low', null=全て）
 * @returns {Promise<Object>} スクレイピング結果
 */
export const runScrape = async (bigquery, db, updateProgress, { 
    startDate, 
    endDate,
    continueOnError = true,
    force = false,
    priorityFilter = null,
} = {}) => {
    const { datasetId, tableIdPrefix } = BIGQUERY;

    // 日付が指定されていない場合はJST基準でデフォルト値を使用
    const start = startDate || getJSTDate(-DEFAULT_SCRAPE_DAYS);
    const end = endDate || getJSTDate(0);

    const options = {
        continueOnError,
        force,
        priorityFilter,
    };

    console.log('スクレイピング処理を開始します...');
    console.log(`  期間: ${start} 〜 ${end}（JST基準）`);
    const result = await scrape(bigquery, datasetId, tableIdPrefix, db, start, end, updateProgress, options);
    console.log('スクレイピング処理が完了しました。');
    
    return result;
};
