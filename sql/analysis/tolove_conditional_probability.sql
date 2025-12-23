-- L+ToLOVEるダークネス 条件付き確率分析
-- 「前N日間がXXXのとき、当日104%以上になる確率は何%か？」
--
-- ベースレートのバイアスを排除するための分析
-- 各期間・各カテゴリの「高設定確率」を比較

-- ============================================================================
-- クエリ1: 期間別 × 前日カテゴリ別の高設定確率（シンプル版）
-- ============================================================================

WITH base_data AS (
  SELECT
    target_date,
    machine_number,
    d1_payout_rate,
    d1_diff,
    
    -- 前日の機械割
    prev_d1_payout_rate,
    -- 前2日の機械割
    prev_d2_payout_rate,
    -- 前3日の機械割
    prev_d3_payout_rate,
    -- 前5日の機械割
    prev_d5_payout_rate,
    -- 前7日の機械割
    prev_d7_payout_rate,
    -- 前28日の機械割
    prev_d28_payout_rate,
    
    -- 長期差枚
    prev_d28_diff,
    
    -- 当日が「高設定」か（104%以上）
    CASE WHEN d1_payout_rate >= 1.04 THEN 1 ELSE 0 END AS is_high_setting

  FROM `yobun-450512.datamart.machine_stats`
  WHERE hole = 'アイランド秋葉原店'
    AND machine = 'L+ToLOVEるダークネス'
    AND target_date >= DATE('2025-11-03')
    AND d1_payout_rate IS NOT NULL
)

-- 各期間ごとの集計をUNION ALL
SELECT * FROM (
  -- 前1日
  SELECT
    'prev_1d' AS period,
    CASE
      WHEN prev_d1_payout_rate < 1.02 THEN '1_low'
      WHEN prev_d1_payout_rate < 1.05 THEN '2_mid'
      ELSE '3_high'
    END AS category,
    COUNT(*) AS sample_count,
    SUM(is_high_setting) AS high_setting_count,
    ROUND(SUM(is_high_setting) / COUNT(*) * 100, 1) AS high_setting_rate,
    ROUND(AVG(d1_payout_rate) * 100, 2) AS avg_payout_rate,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM base_data
  WHERE prev_d1_payout_rate IS NOT NULL
  GROUP BY category

  UNION ALL

  -- 前2日
  SELECT
    'prev_2d' AS period,
    CASE
      WHEN prev_d2_payout_rate < 1.02 THEN '1_low'
      WHEN prev_d2_payout_rate < 1.05 THEN '2_mid'
      ELSE '3_high'
    END AS category,
    COUNT(*) AS sample_count,
    SUM(is_high_setting) AS high_setting_count,
    ROUND(SUM(is_high_setting) / COUNT(*) * 100, 1) AS high_setting_rate,
    ROUND(AVG(d1_payout_rate) * 100, 2) AS avg_payout_rate,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM base_data
  WHERE prev_d2_payout_rate IS NOT NULL
  GROUP BY category

  UNION ALL

  -- 前3日
  SELECT
    'prev_3d' AS period,
    CASE
      WHEN prev_d3_payout_rate < 1.02 THEN '1_low'
      WHEN prev_d3_payout_rate < 1.05 THEN '2_mid'
      ELSE '3_high'
    END AS category,
    COUNT(*) AS sample_count,
    SUM(is_high_setting) AS high_setting_count,
    ROUND(SUM(is_high_setting) / COUNT(*) * 100, 1) AS high_setting_rate,
    ROUND(AVG(d1_payout_rate) * 100, 2) AS avg_payout_rate,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM base_data
  WHERE prev_d3_payout_rate IS NOT NULL
  GROUP BY category

  UNION ALL

  -- 前5日
  SELECT
    'prev_5d' AS period,
    CASE
      WHEN prev_d5_payout_rate < 1.02 THEN '1_low'
      WHEN prev_d5_payout_rate < 1.05 THEN '2_mid'
      ELSE '3_high'
    END AS category,
    COUNT(*) AS sample_count,
    SUM(is_high_setting) AS high_setting_count,
    ROUND(SUM(is_high_setting) / COUNT(*) * 100, 1) AS high_setting_rate,
    ROUND(AVG(d1_payout_rate) * 100, 2) AS avg_payout_rate,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM base_data
  WHERE prev_d5_payout_rate IS NOT NULL
  GROUP BY category

  UNION ALL

  -- 前7日
  SELECT
    'prev_7d' AS period,
    CASE
      WHEN prev_d7_payout_rate < 1.02 THEN '1_low'
      WHEN prev_d7_payout_rate < 1.05 THEN '2_mid'
      ELSE '3_high'
    END AS category,
    COUNT(*) AS sample_count,
    SUM(is_high_setting) AS high_setting_count,
    ROUND(SUM(is_high_setting) / COUNT(*) * 100, 1) AS high_setting_rate,
    ROUND(AVG(d1_payout_rate) * 100, 2) AS avg_payout_rate,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM base_data
  WHERE prev_d7_payout_rate IS NOT NULL
  GROUP BY category

  UNION ALL

  -- 前28日
  SELECT
    'prev_28d' AS period,
    CASE
      WHEN prev_d28_payout_rate < 1.02 THEN '1_low'
      WHEN prev_d28_payout_rate < 1.05 THEN '2_mid'
      ELSE '3_high'
    END AS category,
    COUNT(*) AS sample_count,
    SUM(is_high_setting) AS high_setting_count,
    ROUND(SUM(is_high_setting) / COUNT(*) * 100, 1) AS high_setting_rate,
    ROUND(AVG(d1_payout_rate) * 100, 2) AS avg_payout_rate,
    ROUND(AVG(d1_diff), 0) AS avg_diff
  FROM base_data
  WHERE prev_d28_payout_rate IS NOT NULL
  GROUP BY category
)
ORDER BY period, category;


-- ============================================================================
-- クエリ2: 期間別 × 前日カテゴリ × 長期差枚カテゴリ（詳細版）
-- ============================================================================
/*
WITH base_data AS (
  SELECT
    target_date,
    machine_number,
    d1_payout_rate,
    d1_diff,
    prev_d1_payout_rate,
    prev_d2_payout_rate,
    prev_d3_payout_rate,
    prev_d5_payout_rate,
    prev_d7_payout_rate,
    prev_d28_payout_rate,
    prev_d28_diff,
    CASE WHEN d1_payout_rate >= 1.04 THEN 1 ELSE 0 END AS is_high_setting,
    CASE WHEN prev_d28_diff >= 0 THEN '1_plus' ELSE '2_minus' END AS long_category
  FROM `yobun-450512.datamart.machine_stats`
  WHERE hole = 'アイランド秋葉原店'
    AND machine = 'L+ToLOVEるダークネス'
    AND target_date >= DATE('2025-11-03')
    AND d1_payout_rate IS NOT NULL
    AND prev_d28_diff IS NOT NULL
)

SELECT * FROM (
  -- 前3日 × 長期
  SELECT
    'prev_3d' AS period,
    CASE
      WHEN prev_d3_payout_rate < 1.02 THEN '1_low'
      WHEN prev_d3_payout_rate < 1.05 THEN '2_mid'
      ELSE '3_high'
    END AS short_category,
    long_category,
    COUNT(*) AS sample_count,
    SUM(is_high_setting) AS high_setting_count,
    ROUND(SUM(is_high_setting) / COUNT(*) * 100, 1) AS high_setting_rate,
    ROUND(AVG(d1_payout_rate) * 100, 2) AS avg_payout_rate
  FROM base_data
  WHERE prev_d3_payout_rate IS NOT NULL
  GROUP BY short_category, long_category

  UNION ALL

  -- 前5日 × 長期
  SELECT
    'prev_5d' AS period,
    CASE
      WHEN prev_d5_payout_rate < 1.02 THEN '1_low'
      WHEN prev_d5_payout_rate < 1.05 THEN '2_mid'
      ELSE '3_high'
    END AS short_category,
    long_category,
    COUNT(*),
    SUM(is_high_setting),
    ROUND(SUM(is_high_setting) / COUNT(*) * 100, 1),
    ROUND(AVG(d1_payout_rate) * 100, 2)
  FROM base_data
  WHERE prev_d5_payout_rate IS NOT NULL
  GROUP BY short_category, long_category

  UNION ALL

  -- 前7日 × 長期
  SELECT
    'prev_7d' AS period,
    CASE
      WHEN prev_d7_payout_rate < 1.02 THEN '1_low'
      WHEN prev_d7_payout_rate < 1.05 THEN '2_mid'
      ELSE '3_high'
    END AS short_category,
    long_category,
    COUNT(*),
    SUM(is_high_setting),
    ROUND(SUM(is_high_setting) / COUNT(*) * 100, 1),
    ROUND(AVG(d1_payout_rate) * 100, 2)
  FROM base_data
  WHERE prev_d7_payout_rate IS NOT NULL
  GROUP BY short_category, long_category
)
ORDER BY period, short_category, long_category;
*/


-- ============================================================================
-- クエリ3: ピボット形式（Looker Studio / スプレッドシート向け）
-- ============================================================================
/*
WITH base_data AS (
  SELECT
    target_date,
    machine_number,
    d1_payout_rate,
    prev_d1_payout_rate,
    prev_d2_payout_rate,
    prev_d3_payout_rate,
    prev_d5_payout_rate,
    prev_d7_payout_rate,
    prev_d28_payout_rate,
    CASE WHEN d1_payout_rate >= 1.04 THEN 1 ELSE 0 END AS is_high_setting
  FROM `yobun-450512.datamart.machine_stats`
  WHERE hole = 'アイランド秋葉原店'
    AND machine = 'L+ToLOVEるダークネス'
    AND target_date >= DATE('2025-11-03')
    AND d1_payout_rate IS NOT NULL
)

SELECT
  '1_low (< 102%)' AS category,
  ROUND(SUM(CASE WHEN prev_d1_payout_rate < 1.02 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d1_payout_rate < 1.02 THEN 1 END), 0) * 100, 1) AS prev_1d,
  ROUND(SUM(CASE WHEN prev_d2_payout_rate < 1.02 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d2_payout_rate < 1.02 THEN 1 END), 0) * 100, 1) AS prev_2d,
  ROUND(SUM(CASE WHEN prev_d3_payout_rate < 1.02 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d3_payout_rate < 1.02 THEN 1 END), 0) * 100, 1) AS prev_3d,
  ROUND(SUM(CASE WHEN prev_d5_payout_rate < 1.02 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d5_payout_rate < 1.02 THEN 1 END), 0) * 100, 1) AS prev_5d,
  ROUND(SUM(CASE WHEN prev_d7_payout_rate < 1.02 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d7_payout_rate < 1.02 THEN 1 END), 0) * 100, 1) AS prev_7d,
  ROUND(SUM(CASE WHEN prev_d28_payout_rate < 1.02 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d28_payout_rate < 1.02 THEN 1 END), 0) * 100, 1) AS prev_28d
FROM base_data

UNION ALL

SELECT
  '2_mid (102-105%)' AS category,
  ROUND(SUM(CASE WHEN prev_d1_payout_rate >= 1.02 AND prev_d1_payout_rate < 1.05 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d1_payout_rate >= 1.02 AND prev_d1_payout_rate < 1.05 THEN 1 END), 0) * 100, 1),
  ROUND(SUM(CASE WHEN prev_d2_payout_rate >= 1.02 AND prev_d2_payout_rate < 1.05 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d2_payout_rate >= 1.02 AND prev_d2_payout_rate < 1.05 THEN 1 END), 0) * 100, 1),
  ROUND(SUM(CASE WHEN prev_d3_payout_rate >= 1.02 AND prev_d3_payout_rate < 1.05 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d3_payout_rate >= 1.02 AND prev_d3_payout_rate < 1.05 THEN 1 END), 0) * 100, 1),
  ROUND(SUM(CASE WHEN prev_d5_payout_rate >= 1.02 AND prev_d5_payout_rate < 1.05 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d5_payout_rate >= 1.02 AND prev_d5_payout_rate < 1.05 THEN 1 END), 0) * 100, 1),
  ROUND(SUM(CASE WHEN prev_d7_payout_rate >= 1.02 AND prev_d7_payout_rate < 1.05 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d7_payout_rate >= 1.02 AND prev_d7_payout_rate < 1.05 THEN 1 END), 0) * 100, 1),
  ROUND(SUM(CASE WHEN prev_d28_payout_rate >= 1.02 AND prev_d28_payout_rate < 1.05 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d28_payout_rate >= 1.02 AND prev_d28_payout_rate < 1.05 THEN 1 END), 0) * 100, 1)
FROM base_data

UNION ALL

SELECT
  '3_high (>= 105%)' AS category,
  ROUND(SUM(CASE WHEN prev_d1_payout_rate >= 1.05 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d1_payout_rate >= 1.05 THEN 1 END), 0) * 100, 1),
  ROUND(SUM(CASE WHEN prev_d2_payout_rate >= 1.05 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d2_payout_rate >= 1.05 THEN 1 END), 0) * 100, 1),
  ROUND(SUM(CASE WHEN prev_d3_payout_rate >= 1.05 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d3_payout_rate >= 1.05 THEN 1 END), 0) * 100, 1),
  ROUND(SUM(CASE WHEN prev_d5_payout_rate >= 1.05 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d5_payout_rate >= 1.05 THEN 1 END), 0) * 100, 1),
  ROUND(SUM(CASE WHEN prev_d7_payout_rate >= 1.05 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d7_payout_rate >= 1.05 THEN 1 END), 0) * 100, 1),
  ROUND(SUM(CASE WHEN prev_d28_payout_rate >= 1.05 THEN is_high_setting END) / 
        NULLIF(SUM(CASE WHEN prev_d28_payout_rate >= 1.05 THEN 1 END), 0) * 100, 1)
FROM base_data;
*/
