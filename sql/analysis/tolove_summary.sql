-- L+ToLOVEるダークネス 集計サマリ（視覚化用）- 全期間
-- 短期カテゴリ × 長期カテゴリ別の当日成績を集計

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
      WHEN prev_d3_payout_rate < 1.02 THEN '低め'
      WHEN prev_d3_payout_rate < 1.05 THEN '中間'
      ELSE '高め'
    END AS prev_d3_category,
    
    CASE
      WHEN prev_d5_payout_rate < 1.02 THEN '低め'
      WHEN prev_d5_payout_rate < 1.05 THEN '中間'
      ELSE '高め'
    END AS prev_d5_category,
    
    CASE
      WHEN prev_d7_payout_rate < 1.02 THEN '低め'
      WHEN prev_d7_payout_rate < 1.05 THEN '中間'
      ELSE '高め'
    END AS prev_d7_category,
    
    CASE
      WHEN prev_d28_diff >= 0 THEN 'プラス'
      ELSE 'マイナス'
    END AS prev_d28_diff_category,
    
    -- 期間分類
    CASE
      WHEN target_date BETWEEN DATE('2025-11-03') AND DATE('2025-11-30') THEN '11月'
      WHEN target_date BETWEEN DATE('2025-12-01') AND DATE('2025-12-22') THEN '12月'
    END AS period

  FROM `yobun-450512.datamart.machine_stats`
  WHERE hole = 'アイランド秋葉原店'
    AND machine = 'L+ToLOVEるダークネス'
    AND target_date BETWEEN DATE('2025-11-03') AND DATE('2025-12-22')
    AND prev_d3_payout_rate IS NOT NULL
    AND prev_d28_diff IS NOT NULL
)

-- 3日間の集計
SELECT
  '全期間' AS period,
  '3日間' AS prev_period,
  prev_d3_category AS prev_category,
  prev_d28_diff_category AS long_category,
  COUNT(*) AS sample_count,
  ROUND(AVG(d1_payout_rate), 4) AS avg_d1_payout_rate,
  ROUND(AVG(d1_diff), 1) AS avg_d1_diff
FROM categorized_data
GROUP BY prev_d3_category, prev_d28_diff_category

UNION ALL

-- 5日間の集計
SELECT
  '全期間' AS period,
  '5日間' AS prev_period,
  prev_d5_category AS prev_category,
  prev_d28_diff_category AS long_category,
  COUNT(*) AS sample_count,
  ROUND(AVG(d1_payout_rate), 4) AS avg_d1_payout_rate,
  ROUND(AVG(d1_diff), 1) AS avg_d1_diff
FROM categorized_data
GROUP BY prev_d5_category, prev_d28_diff_category

UNION ALL

-- 7日間の集計
SELECT
  '全期間' AS period,
  '7日間' AS prev_period,
  prev_d7_category AS prev_category,
  prev_d28_diff_category AS long_category,
  COUNT(*) AS sample_count,
  ROUND(AVG(d1_payout_rate), 4) AS avg_d1_payout_rate,
  ROUND(AVG(d1_diff), 1) AS avg_d1_diff
FROM categorized_data
GROUP BY prev_d7_category, prev_d28_diff_category

ORDER BY period, prev_period, prev_category, long_category;

