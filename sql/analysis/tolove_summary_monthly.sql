-- L+ToLOVEるダークネス 月別・期間別の完全集計（視覚化用）
-- 全期間 + 11月 + 12月 × 3日/5日/7日 × カテゴリ別の集計

WITH categorized_data AS (
  SELECT
    target_date,
    machine_number,
    d1_diff,
    d1_payout_rate,
    prev_d3_payout_rate,
    prev_d5_payout_rate,
    prev_d7_payout_rate,
    prev_d28_diff,
    
    CASE
      WHEN prev_d3_payout_rate < 1.02 THEN '1_低め'
      WHEN prev_d3_payout_rate < 1.05 THEN '2_中間'
      ELSE '3_高め'
    END AS prev_d3_category,
    
    CASE
      WHEN prev_d5_payout_rate < 1.02 THEN '1_低め'
      WHEN prev_d5_payout_rate < 1.05 THEN '2_中間'
      ELSE '3_高め'
    END AS prev_d5_category,
    
    CASE
      WHEN prev_d7_payout_rate < 1.02 THEN '1_低め'
      WHEN prev_d7_payout_rate < 1.05 THEN '2_中間'
      ELSE '3_高め'
    END AS prev_d7_category,
    
    CASE
      WHEN prev_d28_diff >= 0 THEN '1_プラス'
      ELSE '2_マイナス'
    END AS prev_d28_diff_category,
    
    CASE
      WHEN target_date BETWEEN DATE('2025-11-03') AND DATE('2025-11-30') THEN '2_11月'
      WHEN target_date BETWEEN DATE('2025-12-01') AND DATE('2025-12-22') THEN '3_12月'
    END AS month_period

  FROM `yobun-450512.datamart.machine_stats`
  WHERE hole = 'アイランド秋葉原店'
    AND machine = 'L+ToLOVEるダークネス'
    AND target_date BETWEEN DATE('2025-11-03') AND DATE('2025-12-22')
    AND prev_d3_payout_rate IS NOT NULL
    AND prev_d28_diff IS NOT NULL
)

-- 全期間 + 月別 × 3日/5日/7日 × カテゴリ
SELECT
  period,
  prev_period,
  prev_category,
  long_category,
  sample_count,
  avg_d1_payout_rate,
  avg_d1_diff
FROM (
  -- 全期間・3日間
  SELECT '1_全期間' AS period, '1_3日間' AS prev_period, prev_d3_category AS prev_category, prev_d28_diff_category AS long_category,
    COUNT(*) AS sample_count, ROUND(AVG(d1_payout_rate), 4) AS avg_d1_payout_rate, ROUND(AVG(d1_diff), 1) AS avg_d1_diff
  FROM categorized_data GROUP BY prev_d3_category, prev_d28_diff_category
  
  UNION ALL
  -- 全期間・5日間
  SELECT '1_全期間', '2_5日間', prev_d5_category, prev_d28_diff_category,
    COUNT(*), ROUND(AVG(d1_payout_rate), 4), ROUND(AVG(d1_diff), 1)
  FROM categorized_data GROUP BY prev_d5_category, prev_d28_diff_category
  
  UNION ALL
  -- 全期間・7日間
  SELECT '1_全期間', '3_7日間', prev_d7_category, prev_d28_diff_category,
    COUNT(*), ROUND(AVG(d1_payout_rate), 4), ROUND(AVG(d1_diff), 1)
  FROM categorized_data GROUP BY prev_d7_category, prev_d28_diff_category
  
  UNION ALL
  -- 11月・3日間
  SELECT '2_11月', '1_3日間', prev_d3_category, prev_d28_diff_category,
    COUNT(*), ROUND(AVG(d1_payout_rate), 4), ROUND(AVG(d1_diff), 1)
  FROM categorized_data WHERE month_period = '2_11月' GROUP BY prev_d3_category, prev_d28_diff_category
  
  UNION ALL
  -- 11月・5日間
  SELECT '2_11月', '2_5日間', prev_d5_category, prev_d28_diff_category,
    COUNT(*), ROUND(AVG(d1_payout_rate), 4), ROUND(AVG(d1_diff), 1)
  FROM categorized_data WHERE month_period = '2_11月' GROUP BY prev_d5_category, prev_d28_diff_category
  
  UNION ALL
  -- 11月・7日間
  SELECT '2_11月', '3_7日間', prev_d7_category, prev_d28_diff_category,
    COUNT(*), ROUND(AVG(d1_payout_rate), 4), ROUND(AVG(d1_diff), 1)
  FROM categorized_data WHERE month_period = '2_11月' GROUP BY prev_d7_category, prev_d28_diff_category
  
  UNION ALL
  -- 12月・3日間
  SELECT '3_12月', '1_3日間', prev_d3_category, prev_d28_diff_category,
    COUNT(*), ROUND(AVG(d1_payout_rate), 4), ROUND(AVG(d1_diff), 1)
  FROM categorized_data WHERE month_period = '3_12月' GROUP BY prev_d3_category, prev_d28_diff_category
  
  UNION ALL
  -- 12月・5日間
  SELECT '3_12月', '2_5日間', prev_d5_category, prev_d28_diff_category,
    COUNT(*), ROUND(AVG(d1_payout_rate), 4), ROUND(AVG(d1_diff), 1)
  FROM categorized_data WHERE month_period = '3_12月' GROUP BY prev_d5_category, prev_d28_diff_category
  
  UNION ALL
  -- 12月・7日間
  SELECT '3_12月', '3_7日間', prev_d7_category, prev_d28_diff_category,
    COUNT(*), ROUND(AVG(d1_payout_rate), 4), ROUND(AVG(d1_diff), 1)
  FROM categorized_data WHERE month_period = '3_12月' GROUP BY prev_d7_category, prev_d28_diff_category
)
ORDER BY period, prev_period, prev_category, long_category;

