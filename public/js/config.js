// ============================================================================
// フロントエンド共通設定
// ============================================================================
// 
// 各ページで使用する設定値とユーティリティ関数
// ============================================================================

// 設定値
const CONFIG = {
    // ページごとのデフォルト表示期間（日数、0=今日のみ）
    defaultDateRanges: {
        dashboard: 28,      // ダッシュボード検索
        datamart: 28,       // データマート検索
        failures: 28,       // 失敗管理フィルタ
        dedupe: 28,         // 重複削除チェック
        sync: 0,            // 同期（今日のみ）
        schedule: 1,        // スケジュール設定
        // 破壊的操作（誤操作防止のため短め推奨）
        rescrape: 28,        // データ再取得（ダッシュボード）
        datamartRun: 1,     // データマート再実行
        delete: 0,          // データ削除（今日のみ）
    },
    // データマート設定
    datamart: {
        concurrency: {
            default: 5,                 // デフォルト並列数
            options: [1, 3, 5, 7, 10, 15, 20, 30, 50, 100],  // UI選択肢
        },
    },
};

/**
 * JST（日本標準時）の日付を取得
 * サーバー側（src/util/date.js）と同じ仕様
 * 
 * @param {number} offset - 日付オフセット（0=今日、-1=昨日、1=明日）
 * @returns {string} YYYY-MM-DD形式の日付文字列
 */
function getJSTDate(offset = 0) {
    const now = new Date();
    const jst = new Date(now.toLocaleString('en-US', { timeZone: 'Asia/Tokyo' }));
    jst.setDate(jst.getDate() + offset);
    return jst.toISOString().split('T')[0];
}
