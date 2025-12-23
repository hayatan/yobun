-- L+ToLOVEるダークネス 特日戦略シミュレーション
-- 特定の日付条件に該当する日に、過去N日間の差枚が最高/最低の台を選んで打った場合の成績
--
-- 対象日付:
--   - 11/3（キャラ誕）
--   - 0のつく日（10, 20, 30）
--   - 1のつく日（1, 11, 21, 31）
--   - 6のつく日（6, 16, 26）
--   - 月最終日

WITH base_data AS (
  SELECT
    target_date,
    machine_number,
    d1_diff,
    d1_payout_rate,
    prev_d3_diff,
    prev_d5_diff,
    prev_d7_diff,
    prev_d28_diff
  FROM `yobun-450512.datamart.machine_stats`
  WHERE hole = 'アイランド秋葉原店'
    AND machine = 'L+ToLOVEるダークネス'
    AND target_date >= DATE('2025-11-03')
    AND d1_diff IS NOT NULL
),

-- 特日フィルタ
special_days AS (
  SELECT *
  FROM base_data
  WHERE 
    -- キャラ誕 11/3
    (EXTRACT(MONTH FROM target_date) = 11 AND EXTRACT(DAY FROM target_date) = 3)
    -- 0のつく日
    OR EXTRACT(DAY FROM target_date) IN (10, 20, 30)
    -- 1のつく日
    OR EXTRACT(DAY FROM target_date) IN (1, 11, 21, 31)
    -- 6のつく日
    OR EXTRACT(DAY FROM target_date) IN (6, 16, 26)
    -- 月最終日
    OR target_date = LAST_DAY(target_date)
),

-- 各日付で prev_d3_diff が最高/最低の台を特定
ranked_d3 AS (
  SELECT
    target_date,
    machine_number,
    d1_diff,
    prev_d3_diff,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d3_diff DESC) AS rank_max,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d3_diff ASC) AS rank_min
  FROM special_days
  WHERE prev_d3_diff IS NOT NULL
),

-- 各日付で prev_d5_diff が最高/最低の台を特定
ranked_d5 AS (
  SELECT
    target_date,
    machine_number,
    d1_diff,
    prev_d5_diff,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d5_diff DESC) AS rank_max,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d5_diff ASC) AS rank_min
  FROM special_days
  WHERE prev_d5_diff IS NOT NULL
),

-- 各日付で prev_d7_diff が最高/最低の台を特定
ranked_d7 AS (
  SELECT
    target_date,
    machine_number,
    d1_diff,
    prev_d7_diff,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d7_diff DESC) AS rank_max,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d7_diff ASC) AS rank_min
  FROM special_days
  WHERE prev_d7_diff IS NOT NULL
),

-- 各日付で prev_d28_diff が最高/最低の台を特定
ranked_d28 AS (
  SELECT
    target_date,
    machine_number,
    d1_diff,
    prev_d28_diff,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d28_diff DESC) AS rank_max,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d28_diff ASC) AS rank_min
  FROM special_days
  WHERE prev_d28_diff IS NOT NULL
)

-- 集計
SELECT * FROM (
  -- prev_3d max
  SELECT
    'prev_3d' AS period,
    'max' AS strategy,
    COUNT(*) AS play_count,
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) AS win_count,
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS win_rate,
    SUM(d1_diff) AS total_diff,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM ranked_d3
  WHERE rank_max = 1

  UNION ALL

  -- prev_3d min
  SELECT
    'prev_3d' AS period,
    'min' AS strategy,
    COUNT(*) AS play_count,
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) AS win_count,
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS win_rate,
    SUM(d1_diff) AS total_diff,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM ranked_d3
  WHERE rank_min = 1

  UNION ALL

  -- prev_5d max
  SELECT
    'prev_5d' AS period,
    'max' AS strategy,
    COUNT(*) AS play_count,
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) AS win_count,
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS win_rate,
    SUM(d1_diff) AS total_diff,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM ranked_d5
  WHERE rank_max = 1

  UNION ALL

  -- prev_5d min
  SELECT
    'prev_5d' AS period,
    'min' AS strategy,
    COUNT(*) AS play_count,
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) AS win_count,
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS win_rate,
    SUM(d1_diff) AS total_diff,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM ranked_d5
  WHERE rank_min = 1

  UNION ALL

  -- prev_7d max
  SELECT
    'prev_7d' AS period,
    'max' AS strategy,
    COUNT(*) AS play_count,
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) AS win_count,
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS win_rate,
    SUM(d1_diff) AS total_diff,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM ranked_d7
  WHERE rank_max = 1

  UNION ALL

  -- prev_7d min
  SELECT
    'prev_7d' AS period,
    'min' AS strategy,
    COUNT(*) AS play_count,
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) AS win_count,
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS win_rate,
    SUM(d1_diff) AS total_diff,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM ranked_d7
  WHERE rank_min = 1

  UNION ALL

  -- prev_28d max
  SELECT
    'prev_28d' AS period,
    'max' AS strategy,
    COUNT(*) AS play_count,
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) AS win_count,
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS win_rate,
    SUM(d1_diff) AS total_diff,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM ranked_d28
  WHERE rank_max = 1

  UNION ALL

  -- prev_28d min
  SELECT
    'prev_28d' AS period,
    'min' AS strategy,
    COUNT(*) AS play_count,
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) AS win_count,
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS win_rate,
    SUM(d1_diff) AS total_diff,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM ranked_d28
  WHERE rank_min = 1
)
ORDER BY period, strategy DESC;

