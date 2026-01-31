-- ============================================================================
-- 組み合わせ戦略検証
-- ============================================================================
--
-- 【概要】
--   日付カテゴリ × 連勝/連敗パターン の組み合わせ効果を検証する。
--   「すべての日」カテゴリを含め、日付に関係なく有効なパターンも確認。
--
-- 【日付カテゴリ】
--   - LINE告知, 月末, 0/1/6/8/9のつく日, 通常日
--   - すべての日（日付カテゴリに関係なく全データ）
--
-- 【連勝/連敗パターン】
--   - 2連勝, 2連敗
--   - 3連勝, 3連敗
--   - 5連勝, 5連敗
--
-- 【出力】
--   組み合わせ別サマリー: 各組み合わせの翌日パフォーマンス
--
-- 【使い方】
--   BigQueryコンソールで実行
--   パラメータを変更する場合は DECLARE 文を編集
--
-- ============================================================================

-- パラメータ定義
DECLARE target_hole STRING DEFAULT 'アイランド秋葉原店';
DECLARE target_machine STRING DEFAULT 'L+ToLOVEるダークネス';
DECLARE eval_start_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 360 DAY);
DECLARE eval_end_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);

-- ============================================================================
-- メインクエリ
-- ============================================================================

WITH
-- ----------------------------------------------------------------------------
-- 1. 対象データの取得
-- ----------------------------------------------------------------------------
base_data AS (
  SELECT
    ms.target_date,
    ms.hole,
    ms.machine,
    ms.machine_number,
    ms.d1_diff,
    ms.d1_game,
    ms.d1_payout_rate,
    CASE WHEN ms.d1_diff > 0 THEN 1 ELSE 0 END AS win,
    ms.prev_d2_win_rate,
    ms.prev_d3_win_rate,
    ms.prev_d5_win_rate
  FROM `yobun-450512.datamart.machine_stats` ms
  WHERE ms.hole = target_hole
    AND ms.machine = target_machine
    AND ms.target_date BETWEEN eval_start_date AND eval_end_date
    AND ms.d1_game IS NOT NULL
    AND ms.d1_game > 0
),

-- ----------------------------------------------------------------------------
-- 2. イベント情報の取得（LINE告知など）
-- ----------------------------------------------------------------------------
events_data AS (
  SELECT
    PARSE_DATE('%Y-%m-%d', date) AS event_date,
    hole,
    event
  FROM `yobun-450512.slot_data.events`
  WHERE hole = target_hole
),

-- ----------------------------------------------------------------------------
-- 3. 日付カテゴリの判定
-- ----------------------------------------------------------------------------
categorized_data AS (
  SELECT
    bd.*,
    ed.event AS event_type,
    -- カテゴリ分類（優先順位: LINE告知 > 月末 > 末尾日 > 通常日）
    CASE
      WHEN ed.event IS NOT NULL THEN 'LINE告知'
      WHEN bd.target_date = LAST_DAY(bd.target_date) THEN '月末'
      WHEN MOD(EXTRACT(DAY FROM bd.target_date), 10) = 0 THEN '0のつく日'
      WHEN MOD(EXTRACT(DAY FROM bd.target_date), 10) = 1 THEN '1のつく日'
      WHEN MOD(EXTRACT(DAY FROM bd.target_date), 10) = 6 THEN '6のつく日'
      WHEN MOD(EXTRACT(DAY FROM bd.target_date), 10) = 8 THEN '8のつく日'
      WHEN MOD(EXTRACT(DAY FROM bd.target_date), 10) = 9 THEN '9のつく日'
      ELSE '通常日'
    END AS day_category
  FROM base_data bd
  LEFT JOIN events_data ed
    ON bd.target_date = ed.event_date
    AND bd.hole = ed.hole
),

-- ----------------------------------------------------------------------------
-- 4. ベースライン計算
-- ----------------------------------------------------------------------------
baseline AS (
  SELECT
    AVG(d1_payout_rate) AS baseline_payout_rate,
    AVG(win) AS baseline_win_rate
  FROM categorized_data
),

-- ----------------------------------------------------------------------------
-- 5. 2連勝/2連敗パターンの組み合わせ
-- ----------------------------------------------------------------------------
combined_d2 AS (
  SELECT
    cd.day_category,
    CASE
      WHEN cd.prev_d2_win_rate = 1.0 THEN '2連勝'
      WHEN cd.prev_d2_win_rate = 0.0 THEN '2連敗'
    END AS streak_pattern,
    cd.d1_diff,
    cd.d1_payout_rate,
    cd.win
  FROM categorized_data cd
  WHERE cd.prev_d2_win_rate IS NOT NULL
    AND (cd.prev_d2_win_rate = 1.0 OR cd.prev_d2_win_rate = 0.0)
),

-- ----------------------------------------------------------------------------
-- 6. 3連勝/3連敗パターンの組み合わせ
-- ----------------------------------------------------------------------------
combined_d3 AS (
  SELECT
    cd.day_category,
    CASE
      WHEN cd.prev_d3_win_rate = 1.0 THEN '3連勝'
      WHEN cd.prev_d3_win_rate = 0.0 THEN '3連敗'
    END AS streak_pattern,
    cd.d1_diff,
    cd.d1_payout_rate,
    cd.win
  FROM categorized_data cd
  WHERE cd.prev_d3_win_rate IS NOT NULL
    AND (cd.prev_d3_win_rate = 1.0 OR cd.prev_d3_win_rate = 0.0)
),

-- ----------------------------------------------------------------------------
-- 7. 5連勝/5連敗パターンの組み合わせ
-- ----------------------------------------------------------------------------
combined_d5 AS (
  SELECT
    cd.day_category,
    CASE
      WHEN cd.prev_d5_win_rate = 1.0 THEN '5連勝'
      WHEN cd.prev_d5_win_rate = 0.0 THEN '5連敗'
    END AS streak_pattern,
    cd.d1_diff,
    cd.d1_payout_rate,
    cd.win
  FROM categorized_data cd
  WHERE cd.prev_d5_win_rate IS NOT NULL
    AND (cd.prev_d5_win_rate = 1.0 OR cd.prev_d5_win_rate = 0.0)
),

-- ----------------------------------------------------------------------------
-- 8. 全組み合わせ統合
-- ----------------------------------------------------------------------------
all_combinations AS (
  SELECT * FROM combined_d2
  UNION ALL
  SELECT * FROM combined_d3
  UNION ALL
  SELECT * FROM combined_d5
),

-- ----------------------------------------------------------------------------
-- 9. 日付カテゴリ別集計
-- ----------------------------------------------------------------------------
category_summary AS (
  SELECT
    day_category,
    streak_pattern,
    COUNT(*) AS sample_count,
    AVG(d1_diff) AS avg_diff,
    AVG(d1_payout_rate) AS avg_payout_rate,
    AVG(win) AS avg_win_rate,
    STDDEV(d1_payout_rate) AS stddev_payout_rate
  FROM all_combinations
  GROUP BY day_category, streak_pattern
),

-- ----------------------------------------------------------------------------
-- 10. 「すべての日」カテゴリ集計
-- ----------------------------------------------------------------------------
all_days_summary AS (
  SELECT
    'すべての日' AS day_category,
    streak_pattern,
    COUNT(*) AS sample_count,
    AVG(d1_diff) AS avg_diff,
    AVG(d1_payout_rate) AS avg_payout_rate,
    AVG(win) AS avg_win_rate,
    STDDEV(d1_payout_rate) AS stddev_payout_rate
  FROM all_combinations
  GROUP BY streak_pattern
),

-- ----------------------------------------------------------------------------
-- 11. 全サマリー統合
-- ----------------------------------------------------------------------------
final_summary AS (
  SELECT * FROM category_summary
  UNION ALL
  SELECT * FROM all_days_summary
)

-- ============================================================================
-- 出力: 組み合わせ別サマリー
-- ============================================================================
SELECT
  fs.day_category,
  fs.streak_pattern,
  fs.sample_count,
  ROUND(fs.avg_diff, 0) AS avg_diff,
  ROUND(fs.avg_payout_rate, 4) AS avg_payout_rate,
  ROUND(fs.avg_win_rate, 4) AS avg_win_rate,
  ROUND(fs.stddev_payout_rate, 4) AS stddev_payout_rate,
  -- ベースラインとの差
  ROUND(fs.avg_payout_rate - b.baseline_payout_rate, 4) AS vs_baseline_payout,
  ROUND(fs.avg_win_rate - b.baseline_win_rate, 4) AS vs_baseline_win,
  -- ソート順
  CASE fs.day_category
    WHEN 'LINE告知' THEN 1
    WHEN '月末' THEN 2
    WHEN '0のつく日' THEN 3
    WHEN '1のつく日' THEN 4
    WHEN '6のつく日' THEN 5
    WHEN '8のつく日' THEN 6
    WHEN '9のつく日' THEN 7
    WHEN '通常日' THEN 8
    WHEN 'すべての日' THEN 9
  END AS day_sort,
  CASE fs.streak_pattern
    WHEN '2連勝' THEN 1
    WHEN '2連敗' THEN 2
    WHEN '3連勝' THEN 3
    WHEN '3連敗' THEN 4
    WHEN '5連勝' THEN 5
    WHEN '5連敗' THEN 6
  END AS streak_sort
FROM final_summary fs
CROSS JOIN baseline b
ORDER BY day_sort, streak_sort;
