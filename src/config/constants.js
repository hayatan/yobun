// ============================================================================
// 定数定義
// ============================================================================
// 
// スクレイピング・データベース関連の定数を集約
// ============================================================================

// BigQuery関連
export const BIGQUERY = {
    datasetId: process.env.BQ_DATASET_ID || 'slot_data',
    tableIdPrefix: 'data_',
    location: 'US',
};

// スクレイピング関連
export const SCRAPING = {
    intervalMs: 1000,           // リクエスト間隔（ミリ秒）
    maxRetries: 3,              // 最大リトライ回数
    batchSize: 1000,            // BigQuery挿入時のバッチサイズ
    tableWaitRetries: 15,       // テーブル作成待機のリトライ回数
    tableWaitDelayMs: 3000,     // テーブル作成待機の間隔（ミリ秒）
    insertMaxRetries: 10,       // BigQuery挿入時の最大リトライ回数
    insertBaseDelayMs: 1000,    // BigQuery挿入時のベース遅延（ミリ秒）
};

// デフォルトのスクレイピング期間
export const DEFAULT_SCRAPE_DAYS = 3;

export default {
    BIGQUERY,
    SCRAPING,
    DEFAULT_SCRAPE_DAYS,
};
