-- L+ToLOVEるダークネス 散布図用データ
-- X軸: 過去N日間の差枚、Y軸: 当日差枚
-- 相関関係を視覚的に確認するためのクエリ

SELECT
  target_date,
  machine_number,
  
  -- 当日データ（Y軸）
  d1_diff,
  d1_payout_rate,
  
  -- 過去N日間の差枚（X軸候補）
  prev_d3_diff,
  prev_d5_diff,
  prev_d7_diff,
  prev_d28_diff,
  
  -- 過去N日間の機械割（参考）
  prev_d3_payout_rate,
  prev_d5_payout_rate,
  prev_d7_payout_rate,
  prev_d28_payout_rate,
  
  -- 長期差枚カテゴリ（色分け用）
  CASE
    WHEN prev_d28_diff >= 0 THEN 'プラス'
    ELSE 'マイナス'
  END AS prev_d28_category,
  
  -- 月（フィルタ用）
  FORMAT_DATE('%Y-%m', target_date) AS month

FROM `yobun-450512.datamart.machine_stats`
WHERE hole = 'アイランド秋葉原店'
  AND machine = 'L+ToLOVEるダークネス'
  AND target_date >= DATE('2025-11-03')
  AND prev_d3_diff IS NOT NULL
  AND prev_d28_diff IS NOT NULL
ORDER BY target_date, machine_number

