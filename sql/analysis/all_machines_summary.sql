-- 全機種対応 集計サマリ（視覚化用）
-- 店舗・機種別 × 短期カテゴリ × 長期カテゴリ の当日成績

WITH categorized_data AS (
  SELECT
    target_date,
    hole,
    machine,
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
    
    FORMAT_DATE('%Y-%m', target_date) AS month

  FROM `yobun-450512.datamart.machine_stats`
  WHERE target_date >= DATE('2025-11-03')
    AND prev_d3_payout_rate IS NOT NULL
    AND prev_d28_diff IS NOT NULL
)

-- 店舗・機種・期間別の集計
SELECT
  hole,
  machine,
  prev_period,
  prev_category,
  long_category,
  sample_count,
  avg_d1_payout_rate,
  avg_d1_diff
FROM (
  -- 3日間
  SELECT 
    hole,
    machine,
    '1_3日間' AS prev_period, 
    prev_d3_category AS prev_category, 
    prev_d28_diff_category AS long_category,
    COUNT(*) AS sample_count, 
    ROUND(AVG(d1_payout_rate), 4) AS avg_d1_payout_rate, 
    ROUND(AVG(d1_diff), 1) AS avg_d1_diff
  FROM categorized_data 
  GROUP BY hole, machine, prev_d3_category, prev_d28_diff_category
  
  UNION ALL
  
  -- 5日間
  SELECT 
    hole,
    machine,
    '2_5日間', 
    prev_d5_category, 
    prev_d28_diff_category,
    COUNT(*), 
    ROUND(AVG(d1_payout_rate), 4), 
    ROUND(AVG(d1_diff), 1)
  FROM categorized_data 
  GROUP BY hole, machine, prev_d5_category, prev_d28_diff_category
  
  UNION ALL
  
  -- 7日間
  SELECT 
    hole,
    machine,
    '3_7日間', 
    prev_d7_category, 
    prev_d28_diff_category,
    COUNT(*), 
    ROUND(AVG(d1_payout_rate), 4), 
    ROUND(AVG(d1_diff), 1)
  FROM categorized_data 
  GROUP BY hole, machine, prev_d7_category, prev_d28_diff_category
)
ORDER BY hole, machine, prev_period, prev_category, long_category

