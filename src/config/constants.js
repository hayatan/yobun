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
    intervalMs: 2000,           // リクエスト間隔（ミリ秒）
    maxRetries: 3,              // 最大リトライ回数
    batchSize: 1000,            // BigQuery挿入時のバッチサイズ
    tableWaitRetries: 15,       // テーブル作成待機のリトライ回数
    tableWaitDelayMs: 3000,     // テーブル作成待機の間隔（ミリ秒）
    insertMaxRetries: 10,       // BigQuery挿入時の最大リトライ回数
    insertBaseDelayMs: 1000,    // BigQuery挿入時のベース遅延（ミリ秒）
    
    // 機種データ取得リトライ設定（指数バックオフ）
    machineRetryMaxAttempts: 3,      // 最大リトライ回数
    machineRetryBaseDelayMs: 5000,   // ベース遅延（ミリ秒）
    machineRetryMaxDelayMs: 30000,   // 最大遅延（ミリ秒）
};

// デフォルトのスクレイピング期間
export const DEFAULT_SCRAPE_DAYS = 3;

// ページごとのデフォルト表示期間（日数、0=今日のみ）
// ※フロントエンドでは public/js/config.js を使用（こちらは参考用）
export const DEFAULT_DATE_RANGES = {
    dashboard: 28,      // ダッシュボード検索
    datamart: 28,       // データマート検索
    failures: 28,       // 失敗管理フィルタ
    dedupe: 28,         // 重複削除チェック
    sync: 0,            // 同期（今日のみ）
    schedule: 1,        // スケジュール設定
    // 破壊的操作（誤操作防止のため短め推奨）
    rescrape: 1,        // データ再取得（ダッシュボード）
    datamartRun: 1,     // データマート再実行
    delete: 0,          // データ削除（今日のみ）
};

export default {
    BIGQUERY,
    SCRAPING,
    DEFAULT_SCRAPE_DAYS,
    DEFAULT_DATE_RANGES,
};
