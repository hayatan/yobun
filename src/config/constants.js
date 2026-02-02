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
    tableWaitRetries: 15,       // テーブル作成待機のリトライ回数
    tableWaitDelayMs: 3000,     // テーブル作成待機の間隔（ミリ秒）
    
    // 機種データ取得リトライ設定（指数バックオフ）
    machineRetryMaxAttempts: 5,      // 最大リトライ回数
    machineRetryBaseDelayMs: 5000,   // ベース遅延（ミリ秒）
    machineRetryMaxDelayMs: 30000,   // 最大遅延（ミリ秒）
};

// データマート関連
export const DATAMART = {
    // バックフィル並列実行設定
    concurrency: {
        default: 10,     // デフォルト並列数
        min: 1,         // 最小並列数
        max: 100,        // 最大並列数
    },
    // リトライ設定
    retry: {
        maxAttempts: 3,     // 最大リトライ回数（初回実行含む）
        delayMs: 5000,      // リトライ間隔（ミリ秒）
    },
    // 並列実行時のタスク開始間隔（ミリ秒）
    // 200ms = 秒間最大5タスク開始（10 DML/秒の制限を回避）
    intervalMs: 500,
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
    DATAMART,
    DEFAULT_SCRAPE_DAYS,
    DEFAULT_DATE_RANGES,
};
