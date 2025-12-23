-- L+ToLOVEるダークネス 詳細データ出力（AI分析用CSV）
-- アイランド秋葉原店の台別データを分析用に出力
--
-- 使用方法:
--   1. BigQueryコンソールで実行
--   2. 結果をCSVでエクスポート
--   3. AIに分析を依頼

WITH categorized_data AS (
  SELECT
    target_date,
    machine_number,
    machine,
    
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
      WHEN prev_d3_payout_rate < 1.02 THEN '低め'
      WHEN prev_d3_payout_rate < 1.05 THEN '中間'
      ELSE '高め'
    END AS prev_d3_category,
    
    -- 短期5日カテゴリ
    CASE
      WHEN prev_d5_payout_rate < 1.02 THEN '低め'
      WHEN prev_d5_payout_rate < 1.05 THEN '中間'
      ELSE '高め'
    END AS prev_d5_category,
    
    -- 短期7日カテゴリ
    CASE
      WHEN prev_d7_payout_rate < 1.02 THEN '低め'
      WHEN prev_d7_payout_rate < 1.05 THEN '中間'
      ELSE '高め'
    END AS prev_d7_category,
    
    -- 長期28日差枚カテゴリ
    CASE
      WHEN prev_d28_diff >= 0 THEN 'プラス'
      ELSE 'マイナス'
    END AS prev_d28_diff_category

  FROM `yobun-450512.datamart.machine_stats`
  WHERE hole = 'アイランド秋葉原店'
    AND machine = 'L+ToLOVEるダークネス'
    AND target_date BETWEEN DATE('2025-11-03') AND DATE('2025-12-22')
    AND prev_d3_payout_rate IS NOT NULL
    AND prev_d28_diff IS NOT NULL
)

SELECT * FROM categorized_data
ORDER BY target_date, machine_number;

