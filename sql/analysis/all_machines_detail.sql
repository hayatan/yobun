-- 全機種対応 詳細データ出力（AI分析用CSV）
-- Looker Studio でフィルタを使って機種を選択可能
--
-- 使用方法:
--   1. BigQueryまたはLooker Studioで実行
--   2. 店舗・機種をフィルタで絞り込み

SELECT
  target_date,
  hole,
  machine,
  machine_number,
  
  -- 当日データ
  d1_diff,
  d1_game,
  d1_payout_rate,
  
  -- 前日からの短期データ（当日を含まない）
  prev_d3_diff,
  prev_d3_game,
  prev_d3_payout_rate,
  prev_d5_diff,
  prev_d5_game,
  prev_d5_payout_rate,
  prev_d7_diff,
  prev_d7_game,
  prev_d7_payout_rate,
  
  -- 長期データ
  prev_d28_diff,
  prev_d28_game,
  prev_d28_payout_rate,
  
  -- 短期3日カテゴリ
  CASE
    WHEN prev_d3_payout_rate < 1.02 THEN '1_低め'
    WHEN prev_d3_payout_rate < 1.05 THEN '2_中間'
    ELSE '3_高め'
  END AS prev_d3_category,
  
  -- 短期5日カテゴリ
  CASE
    WHEN prev_d5_payout_rate < 1.02 THEN '1_低め'
    WHEN prev_d5_payout_rate < 1.05 THEN '2_中間'
    ELSE '3_高め'
  END AS prev_d5_category,
  
  -- 短期7日カテゴリ
  CASE
    WHEN prev_d7_payout_rate < 1.02 THEN '1_低め'
    WHEN prev_d7_payout_rate < 1.05 THEN '2_中間'
    ELSE '3_高め'
  END AS prev_d7_category,
  
  -- 長期28日差枚カテゴリ
  CASE
    WHEN prev_d28_diff >= 0 THEN '1_プラス'
    ELSE '2_マイナス'
  END AS prev_d28_diff_category,
  
  -- 月（フィルタ用）
  FORMAT_DATE('%Y-%m', target_date) AS month

FROM `yobun-450512.datamart.machine_stats`
WHERE target_date >= DATE('2025-11-03')
  AND prev_d3_payout_rate IS NOT NULL
  AND prev_d28_diff IS NOT NULL
ORDER BY hole, machine, target_date, machine_number

