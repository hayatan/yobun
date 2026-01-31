-- ============================================================================
-- 連勝/連敗効果検証
-- ============================================================================
--
-- 【概要】
--   2連勝/2連敗、3連勝/3連敗、5連勝/5連敗 の各パターン別に、
--   翌日のパフォーマンスを検証する。
--   「連勝台は翌日も強い」「連敗台は反発する」などの仮説を検証。
--
-- 【パターン】
--   - 2連勝/2連敗: prev_d2_win_rate = 1.0/0.0
--   - 3連勝/3連敗: prev_d3_win_rate = 1.0/0.0
--   - 5連勝/5連敗: prev_d5_win_rate = 1.0/0.0
--   ※ 4連勝/4連敗はdatamartに対応カラムがないため省略
--
-- 【出力】
--   パターン別サマリー: 各パターンの翌日パフォーマンス
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
    -- 当日のパフォーマンス
    ms.d1_diff,
    ms.d1_game,
    ms.d1_payout_rate,
    CASE WHEN ms.d1_diff > 0 THEN 1 ELSE 0 END AS win,
    -- 前日からの勝率（予測に使用する情報）
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
-- 2. ベースライン計算
-- ----------------------------------------------------------------------------
baseline AS (
  SELECT
    AVG(d1_payout_rate) AS baseline_payout_rate,
    AVG(win) AS baseline_win_rate
  FROM base_data
),

-- ----------------------------------------------------------------------------
-- 3. 2連勝/2連敗パターン
-- ----------------------------------------------------------------------------
d2_data AS (
  SELECT
    bd.*,
    CASE
      WHEN prev_d2_win_rate = 1.0 THEN '2連勝'
      WHEN prev_d2_win_rate = 0.0 THEN '2連敗'
      ELSE NULL
    END AS streak_pattern
  FROM base_data bd
  WHERE prev_d2_win_rate IS NOT NULL
    AND (prev_d2_win_rate = 1.0 OR prev_d2_win_rate = 0.0)
),

d2_summary AS (
  SELECT
    '2日間' AS period,
    streak_pattern,
    COUNT(*) AS sample_count,
    AVG(d1_diff) AS avg_diff,
    AVG(d1_payout_rate) AS avg_payout_rate,
    AVG(win) AS avg_win_rate,
    STDDEV(d1_payout_rate) AS stddev_payout_rate
  FROM d2_data
  GROUP BY streak_pattern
),

-- ----------------------------------------------------------------------------
-- 4. 3連勝/3連敗パターン
-- ----------------------------------------------------------------------------
d3_data AS (
  SELECT
    bd.*,
    CASE
      WHEN prev_d3_win_rate = 1.0 THEN '3連勝'
      WHEN prev_d3_win_rate = 0.0 THEN '3連敗'
      ELSE NULL
    END AS streak_pattern
  FROM base_data bd
  WHERE prev_d3_win_rate IS NOT NULL
    AND (prev_d3_win_rate = 1.0 OR prev_d3_win_rate = 0.0)
),

d3_summary AS (
  SELECT
    '3日間' AS period,
    streak_pattern,
    COUNT(*) AS sample_count,
    AVG(d1_diff) AS avg_diff,
    AVG(d1_payout_rate) AS avg_payout_rate,
    AVG(win) AS avg_win_rate,
    STDDEV(d1_payout_rate) AS stddev_payout_rate
  FROM d3_data
  GROUP BY streak_pattern
),

-- ----------------------------------------------------------------------------
-- 5. 5連勝/5連敗パターン
-- ----------------------------------------------------------------------------
d5_data AS (
  SELECT
    bd.*,
    CASE
      WHEN prev_d5_win_rate = 1.0 THEN '5連勝'
      WHEN prev_d5_win_rate = 0.0 THEN '5連敗'
      ELSE NULL
    END AS streak_pattern
  FROM base_data bd
  WHERE prev_d5_win_rate IS NOT NULL
    AND (prev_d5_win_rate = 1.0 OR prev_d5_win_rate = 0.0)
),

d5_summary AS (
  SELECT
    '5日間' AS period,
    streak_pattern,
    COUNT(*) AS sample_count,
    AVG(d1_diff) AS avg_diff,
    AVG(d1_payout_rate) AS avg_payout_rate,
    AVG(win) AS avg_win_rate,
    STDDEV(d1_payout_rate) AS stddev_payout_rate
  FROM d5_data
  GROUP BY streak_pattern
),

-- ----------------------------------------------------------------------------
-- 6. 全パターン統合
-- ----------------------------------------------------------------------------
all_patterns AS (
  SELECT * FROM d2_summary
  UNION ALL
  SELECT * FROM d3_summary
  UNION ALL
  SELECT * FROM d5_summary
)

-- ============================================================================
-- 出力: パターン別サマリー
-- ============================================================================
SELECT
  ap.period,
  ap.streak_pattern,
  ap.sample_count,
  ROUND(ap.avg_diff, 0) AS avg_diff,
  ROUND(ap.avg_payout_rate, 4) AS avg_payout_rate,
  ROUND(ap.avg_win_rate, 4) AS avg_win_rate,
  ROUND(ap.stddev_payout_rate, 4) AS stddev_payout_rate,
  -- ベースラインとの差
  ROUND(ap.avg_payout_rate - b.baseline_payout_rate, 4) AS vs_baseline_payout,
  ROUND(ap.avg_win_rate - b.baseline_win_rate, 4) AS vs_baseline_win,
  -- ソート順
  CASE ap.period
    WHEN '2日間' THEN 1
    WHEN '3日間' THEN 2
    WHEN '5日間' THEN 3
  END AS period_order,
  CASE ap.streak_pattern
    WHEN '2連勝' THEN 1
    WHEN '2連敗' THEN 2
    WHEN '3連勝' THEN 1
    WHEN '3連敗' THEN 2
    WHEN '5連勝' THEN 1
    WHEN '5連敗' THEN 2
  END AS pattern_order
FROM all_patterns ap
CROSS JOIN baseline b
ORDER BY period_order, pattern_order;
