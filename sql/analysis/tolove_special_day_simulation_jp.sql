-- L+ToLOVEるダークネス 戦略シミュレーション（日本語版）
-- 様々な条件で台を選んで打った場合の成績
--
-- 曜日カテゴリ:
--   - 全日（曜日無考慮）
--   - 平日（土日祝以外）
--   - 土日祝
--   - 特日（0のつく日、1のつく日、6のつく日、月最終日）
--
-- 戦略:
--   - 差枚ベスト1/3、ワースト1/3
--   - 勝率100%、60%以上、30%以下、0%

WITH base_data AS (
  SELECT
    target_date,
    machine_number,
    d1_diff,
    d1_game,
    d1_payout_rate,
    prev_d1_diff,
    prev_d3_diff,
    prev_d5_diff,
    prev_d7_diff,
    prev_d28_diff,
    prev_d3_win_rate,
    prev_d5_win_rate,
    prev_d7_win_rate,
    prev_d28_win_rate,
    -- 土日祝フラグ
    CASE 
      WHEN EXTRACT(DAYOFWEEK FROM target_date) IN (1, 7) THEN TRUE  -- 日曜=1, 土曜=7
      WHEN bqfunc.holidays_in_japan__us.holiday_name(target_date) IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS is_holiday,
    -- 特日フラグ（0のつく日、1のつく日、6のつく日、月最終日）※キャラ誕除外
    CASE 
      WHEN EXTRACT(DAY FROM target_date) IN (10, 20, 30) THEN TRUE  -- 0のつく日
      WHEN EXTRACT(DAY FROM target_date) IN (1, 11, 21, 31) THEN TRUE  -- 1のつく日
      WHEN EXTRACT(DAY FROM target_date) IN (6, 16, 26) THEN TRUE  -- 6のつく日
      WHEN target_date = LAST_DAY(target_date) THEN TRUE  -- 月最終日
      ELSE FALSE
    END AS is_special_day
  FROM `yobun-450512.datamart.machine_stats`
  WHERE hole = 'アイランド秋葉原店'
    AND machine = 'L+ToLOVEるダークネス'
    AND target_date >= DATE('2025-11-03')
    AND d1_diff IS NOT NULL
),

-- ============================================================================
-- 差枚ランキング
-- ============================================================================
ranked_d1_all AS (
  SELECT target_date, machine_number, d1_diff, d1_game, prev_d1_diff, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d1_diff DESC) AS rank_best,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d1_diff ASC) AS rank_worst
  FROM base_data WHERE prev_d1_diff IS NOT NULL
),
ranked_d3_all AS (
  SELECT target_date, machine_number, d1_diff, d1_game, prev_d3_diff, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d3_diff DESC) AS rank_best,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d3_diff ASC) AS rank_worst
  FROM base_data WHERE prev_d3_diff IS NOT NULL
),
ranked_d5_all AS (
  SELECT target_date, machine_number, d1_diff, d1_game, prev_d5_diff, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d5_diff DESC) AS rank_best,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d5_diff ASC) AS rank_worst
  FROM base_data WHERE prev_d5_diff IS NOT NULL
),
ranked_d7_all AS (
  SELECT target_date, machine_number, d1_diff, d1_game, prev_d7_diff, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d7_diff DESC) AS rank_best,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d7_diff ASC) AS rank_worst
  FROM base_data WHERE prev_d7_diff IS NOT NULL
),
ranked_d28_all AS (
  SELECT target_date, machine_number, d1_diff, d1_game, prev_d28_diff, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d28_diff DESC) AS rank_best,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d28_diff ASC) AS rank_worst
  FROM base_data WHERE prev_d28_diff IS NOT NULL
),

-- ============================================================================
-- 勝率フィルタ
-- ============================================================================
winrate_d3_all AS (
  SELECT target_date, machine_number, d1_diff, d1_game, prev_d3_win_rate, is_holiday, is_special_day
  FROM base_data WHERE prev_d3_win_rate IS NOT NULL
),
winrate_d5_all AS (
  SELECT target_date, machine_number, d1_diff, d1_game, prev_d5_win_rate, is_holiday, is_special_day
  FROM base_data WHERE prev_d5_win_rate IS NOT NULL
),
winrate_d7_all AS (
  SELECT target_date, machine_number, d1_diff, d1_game, prev_d7_win_rate, is_holiday, is_special_day
  FROM base_data WHERE prev_d7_win_rate IS NOT NULL
),
winrate_d28_all AS (
  SELECT target_date, machine_number, d1_diff, d1_game, prev_d28_win_rate, is_holiday, is_special_day
  FROM base_data WHERE prev_d28_win_rate IS NOT NULL
)

-- ============================================================================
-- 集計
-- ============================================================================
SELECT
  `曜日`,
  `参照期間`,
  `戦略`,
  `実施日数`,
  `参照台数`,
  `勝利日数`,
  `勝率`,
  `合計差枚`,
  `平均差枚`,
  `機械割`
FROM (
  -- ========================================
  -- 全日（曜日無考慮）
  -- ========================================
  
  -- ========== 前日 差枚ベース ==========
  SELECT '全日' AS `曜日`, '前日' AS `参照期間`, '差枚ベスト1' AS `戦略`,
    COUNT(DISTINCT target_date) AS `実施日数`, COUNT(*) AS `参照台数`,
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) AS `勝利日数`,
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS `勝率`,
    SUM(d1_diff) AS `合計差枚`, ROUND(AVG(d1_diff), 0) AS `平均差枚`,
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2) AS `機械割`,
    101 AS sort_order
  FROM ranked_d1_all WHERE rank_best = 1
  UNION ALL
  SELECT '全日', '前日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 102
  FROM ranked_d1_all WHERE rank_best <= 3
  UNION ALL
  SELECT '全日', '前日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 103
  FROM ranked_d1_all WHERE rank_worst = 1
  UNION ALL
  SELECT '全日', '前日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 104
  FROM ranked_d1_all WHERE rank_worst <= 3

  UNION ALL

  -- ========== 過去3日 差枚ベース ==========
  SELECT '全日', '過去3日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 110
  FROM ranked_d3_all WHERE rank_best = 1
  UNION ALL
  SELECT '全日', '過去3日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 111
  FROM ranked_d3_all WHERE rank_best <= 3
  UNION ALL
  SELECT '全日', '過去3日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 112
  FROM ranked_d3_all WHERE rank_worst = 1
  UNION ALL
  SELECT '全日', '過去3日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 113
  FROM ranked_d3_all WHERE rank_worst <= 3
  UNION ALL
  -- 勝率ベース
  SELECT '全日', '過去3日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 114
  FROM winrate_d3_all WHERE prev_d3_win_rate = 1.0
  UNION ALL
  SELECT '全日', '過去3日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 115
  FROM winrate_d3_all WHERE prev_d3_win_rate >= 0.6
  UNION ALL
  SELECT '全日', '過去3日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 116
  FROM winrate_d3_all WHERE prev_d3_win_rate <= 0.3
  UNION ALL
  SELECT '全日', '過去3日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 117
  FROM winrate_d3_all WHERE prev_d3_win_rate = 0

  UNION ALL

  -- ========== 過去5日 差枚ベース ==========
  SELECT '全日', '過去5日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 120
  FROM ranked_d5_all WHERE rank_best = 1
  UNION ALL
  SELECT '全日', '過去5日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 121
  FROM ranked_d5_all WHERE rank_best <= 3
  UNION ALL
  SELECT '全日', '過去5日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 122
  FROM ranked_d5_all WHERE rank_worst = 1
  UNION ALL
  SELECT '全日', '過去5日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 123
  FROM ranked_d5_all WHERE rank_worst <= 3
  UNION ALL
  -- 勝率ベース
  SELECT '全日', '過去5日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 124
  FROM winrate_d5_all WHERE prev_d5_win_rate = 1.0
  UNION ALL
  SELECT '全日', '過去5日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 125
  FROM winrate_d5_all WHERE prev_d5_win_rate >= 0.6
  UNION ALL
  SELECT '全日', '過去5日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 126
  FROM winrate_d5_all WHERE prev_d5_win_rate <= 0.3
  UNION ALL
  SELECT '全日', '過去5日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 127
  FROM winrate_d5_all WHERE prev_d5_win_rate = 0

  UNION ALL

  -- ========== 過去7日 差枚ベース ==========
  SELECT '全日', '過去7日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 130
  FROM ranked_d7_all WHERE rank_best = 1
  UNION ALL
  SELECT '全日', '過去7日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 131
  FROM ranked_d7_all WHERE rank_best <= 3
  UNION ALL
  SELECT '全日', '過去7日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 132
  FROM ranked_d7_all WHERE rank_worst = 1
  UNION ALL
  SELECT '全日', '過去7日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 133
  FROM ranked_d7_all WHERE rank_worst <= 3
  UNION ALL
  -- 勝率ベース
  SELECT '全日', '過去7日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 134
  FROM winrate_d7_all WHERE prev_d7_win_rate = 1.0
  UNION ALL
  SELECT '全日', '過去7日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 135
  FROM winrate_d7_all WHERE prev_d7_win_rate >= 0.6
  UNION ALL
  SELECT '全日', '過去7日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 136
  FROM winrate_d7_all WHERE prev_d7_win_rate <= 0.3
  UNION ALL
  SELECT '全日', '過去7日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 137
  FROM winrate_d7_all WHERE prev_d7_win_rate = 0

  UNION ALL

  -- ========== 過去28日 差枚ベース ==========
  SELECT '全日', '過去28日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 140
  FROM ranked_d28_all WHERE rank_best = 1
  UNION ALL
  SELECT '全日', '過去28日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 141
  FROM ranked_d28_all WHERE rank_best <= 3
  UNION ALL
  SELECT '全日', '過去28日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 142
  FROM ranked_d28_all WHERE rank_worst = 1
  UNION ALL
  SELECT '全日', '過去28日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 143
  FROM ranked_d28_all WHERE rank_worst <= 3
  UNION ALL
  -- 勝率ベース
  SELECT '全日', '過去28日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 144
  FROM winrate_d28_all WHERE prev_d28_win_rate = 1.0
  UNION ALL
  SELECT '全日', '過去28日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 145
  FROM winrate_d28_all WHERE prev_d28_win_rate >= 0.6
  UNION ALL
  SELECT '全日', '過去28日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 146
  FROM winrate_d28_all WHERE prev_d28_win_rate <= 0.3
  UNION ALL
  SELECT '全日', '過去28日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 147
  FROM winrate_d28_all WHERE prev_d28_win_rate = 0

  UNION ALL

  -- ========================================
  -- 平日のみ
  -- ========================================
  
  -- ========== 前日 差枚ベース ==========
  SELECT '平日', '前日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 201
  FROM ranked_d1_all WHERE rank_best = 1 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '前日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 202
  FROM ranked_d1_all WHERE rank_best <= 3 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '前日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 203
  FROM ranked_d1_all WHERE rank_worst = 1 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '前日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 204
  FROM ranked_d1_all WHERE rank_worst <= 3 AND is_holiday = FALSE

  UNION ALL

  -- ========== 過去3日 ==========
  SELECT '平日', '過去3日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 210
  FROM ranked_d3_all WHERE rank_best = 1 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去3日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 211
  FROM ranked_d3_all WHERE rank_best <= 3 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去3日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 212
  FROM ranked_d3_all WHERE rank_worst = 1 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去3日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 213
  FROM ranked_d3_all WHERE rank_worst <= 3 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去3日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 214
  FROM winrate_d3_all WHERE prev_d3_win_rate = 1.0 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去3日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 215
  FROM winrate_d3_all WHERE prev_d3_win_rate >= 0.6 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去3日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 216
  FROM winrate_d3_all WHERE prev_d3_win_rate <= 0.3 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去3日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 217
  FROM winrate_d3_all WHERE prev_d3_win_rate = 0 AND is_holiday = FALSE

  UNION ALL

  -- ========== 過去5日 ==========
  SELECT '平日', '過去5日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 220
  FROM ranked_d5_all WHERE rank_best = 1 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去5日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 221
  FROM ranked_d5_all WHERE rank_best <= 3 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去5日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 222
  FROM ranked_d5_all WHERE rank_worst = 1 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去5日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 223
  FROM ranked_d5_all WHERE rank_worst <= 3 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去5日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 224
  FROM winrate_d5_all WHERE prev_d5_win_rate = 1.0 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去5日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 225
  FROM winrate_d5_all WHERE prev_d5_win_rate >= 0.6 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去5日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 226
  FROM winrate_d5_all WHERE prev_d5_win_rate <= 0.3 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去5日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 227
  FROM winrate_d5_all WHERE prev_d5_win_rate = 0 AND is_holiday = FALSE

  UNION ALL

  -- ========== 過去7日 ==========
  SELECT '平日', '過去7日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 230
  FROM ranked_d7_all WHERE rank_best = 1 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去7日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 231
  FROM ranked_d7_all WHERE rank_best <= 3 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去7日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 232
  FROM ranked_d7_all WHERE rank_worst = 1 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去7日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 233
  FROM ranked_d7_all WHERE rank_worst <= 3 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去7日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 234
  FROM winrate_d7_all WHERE prev_d7_win_rate = 1.0 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去7日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 235
  FROM winrate_d7_all WHERE prev_d7_win_rate >= 0.6 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去7日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 236
  FROM winrate_d7_all WHERE prev_d7_win_rate <= 0.3 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去7日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 237
  FROM winrate_d7_all WHERE prev_d7_win_rate = 0 AND is_holiday = FALSE

  UNION ALL

  -- ========== 過去28日 ==========
  SELECT '平日', '過去28日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 240
  FROM ranked_d28_all WHERE rank_best = 1 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去28日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 241
  FROM ranked_d28_all WHERE rank_best <= 3 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去28日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 242
  FROM ranked_d28_all WHERE rank_worst = 1 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去28日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 243
  FROM ranked_d28_all WHERE rank_worst <= 3 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去28日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 244
  FROM winrate_d28_all WHERE prev_d28_win_rate = 1.0 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去28日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 245
  FROM winrate_d28_all WHERE prev_d28_win_rate >= 0.6 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去28日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 246
  FROM winrate_d28_all WHERE prev_d28_win_rate <= 0.3 AND is_holiday = FALSE
  UNION ALL
  SELECT '平日', '過去28日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 247
  FROM winrate_d28_all WHERE prev_d28_win_rate = 0 AND is_holiday = FALSE

  UNION ALL

  -- ========================================
  -- 土日祝のみ
  -- ========================================
  
  -- ========== 前日 差枚ベース ==========
  SELECT '土日祝', '前日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 301
  FROM ranked_d1_all WHERE rank_best = 1 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '前日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 302
  FROM ranked_d1_all WHERE rank_best <= 3 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '前日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 303
  FROM ranked_d1_all WHERE rank_worst = 1 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '前日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 304
  FROM ranked_d1_all WHERE rank_worst <= 3 AND is_holiday = TRUE

  UNION ALL

  -- ========== 過去3日 ==========
  SELECT '土日祝', '過去3日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 310
  FROM ranked_d3_all WHERE rank_best = 1 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去3日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 311
  FROM ranked_d3_all WHERE rank_best <= 3 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去3日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 312
  FROM ranked_d3_all WHERE rank_worst = 1 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去3日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 313
  FROM ranked_d3_all WHERE rank_worst <= 3 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去3日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 314
  FROM winrate_d3_all WHERE prev_d3_win_rate = 1.0 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去3日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 315
  FROM winrate_d3_all WHERE prev_d3_win_rate >= 0.6 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去3日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 316
  FROM winrate_d3_all WHERE prev_d3_win_rate <= 0.3 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去3日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 317
  FROM winrate_d3_all WHERE prev_d3_win_rate = 0 AND is_holiday = TRUE

  UNION ALL

  -- ========== 過去5日 ==========
  SELECT '土日祝', '過去5日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 320
  FROM ranked_d5_all WHERE rank_best = 1 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去5日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 321
  FROM ranked_d5_all WHERE rank_best <= 3 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去5日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 322
  FROM ranked_d5_all WHERE rank_worst = 1 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去5日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 323
  FROM ranked_d5_all WHERE rank_worst <= 3 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去5日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 324
  FROM winrate_d5_all WHERE prev_d5_win_rate = 1.0 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去5日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 325
  FROM winrate_d5_all WHERE prev_d5_win_rate >= 0.6 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去5日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 326
  FROM winrate_d5_all WHERE prev_d5_win_rate <= 0.3 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去5日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 327
  FROM winrate_d5_all WHERE prev_d5_win_rate = 0 AND is_holiday = TRUE

  UNION ALL

  -- ========== 過去7日 ==========
  SELECT '土日祝', '過去7日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 330
  FROM ranked_d7_all WHERE rank_best = 1 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去7日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 331
  FROM ranked_d7_all WHERE rank_best <= 3 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去7日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 332
  FROM ranked_d7_all WHERE rank_worst = 1 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去7日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 333
  FROM ranked_d7_all WHERE rank_worst <= 3 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去7日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 334
  FROM winrate_d7_all WHERE prev_d7_win_rate = 1.0 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去7日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 335
  FROM winrate_d7_all WHERE prev_d7_win_rate >= 0.6 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去7日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 336
  FROM winrate_d7_all WHERE prev_d7_win_rate <= 0.3 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去7日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 337
  FROM winrate_d7_all WHERE prev_d7_win_rate = 0 AND is_holiday = TRUE

  UNION ALL

  -- ========== 過去28日 ==========
  SELECT '土日祝', '過去28日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 340
  FROM ranked_d28_all WHERE rank_best = 1 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去28日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 341
  FROM ranked_d28_all WHERE rank_best <= 3 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去28日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 342
  FROM ranked_d28_all WHERE rank_worst = 1 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去28日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 343
  FROM ranked_d28_all WHERE rank_worst <= 3 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去28日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 344
  FROM winrate_d28_all WHERE prev_d28_win_rate = 1.0 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去28日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 345
  FROM winrate_d28_all WHERE prev_d28_win_rate >= 0.6 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去28日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 346
  FROM winrate_d28_all WHERE prev_d28_win_rate <= 0.3 AND is_holiday = TRUE
  UNION ALL
  SELECT '土日祝', '過去28日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 347
  FROM winrate_d28_all WHERE prev_d28_win_rate = 0 AND is_holiday = TRUE

  UNION ALL

  -- ========================================
  -- 特日のみ
  -- ========================================
  
  -- ========== 前日 差枚ベース ==========
  SELECT '特日', '前日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 401
  FROM ranked_d1_all WHERE rank_best = 1 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '前日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 402
  FROM ranked_d1_all WHERE rank_best <= 3 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '前日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 403
  FROM ranked_d1_all WHERE rank_worst = 1 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '前日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 404
  FROM ranked_d1_all WHERE rank_worst <= 3 AND is_special_day = TRUE

  UNION ALL

  -- ========== 過去3日 ==========
  SELECT '特日', '過去3日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 410
  FROM ranked_d3_all WHERE rank_best = 1 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去3日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 411
  FROM ranked_d3_all WHERE rank_best <= 3 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去3日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 412
  FROM ranked_d3_all WHERE rank_worst = 1 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去3日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 413
  FROM ranked_d3_all WHERE rank_worst <= 3 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去3日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 414
  FROM winrate_d3_all WHERE prev_d3_win_rate = 1.0 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去3日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 415
  FROM winrate_d3_all WHERE prev_d3_win_rate >= 0.6 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去3日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 416
  FROM winrate_d3_all WHERE prev_d3_win_rate <= 0.3 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去3日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 417
  FROM winrate_d3_all WHERE prev_d3_win_rate = 0 AND is_special_day = TRUE

  UNION ALL

  -- ========== 過去5日 ==========
  SELECT '特日', '過去5日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 420
  FROM ranked_d5_all WHERE rank_best = 1 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去5日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 421
  FROM ranked_d5_all WHERE rank_best <= 3 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去5日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 422
  FROM ranked_d5_all WHERE rank_worst = 1 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去5日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 423
  FROM ranked_d5_all WHERE rank_worst <= 3 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去5日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 424
  FROM winrate_d5_all WHERE prev_d5_win_rate = 1.0 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去5日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 425
  FROM winrate_d5_all WHERE prev_d5_win_rate >= 0.6 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去5日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 426
  FROM winrate_d5_all WHERE prev_d5_win_rate <= 0.3 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去5日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 427
  FROM winrate_d5_all WHERE prev_d5_win_rate = 0 AND is_special_day = TRUE

  UNION ALL

  -- ========== 過去7日 ==========
  SELECT '特日', '過去7日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 430
  FROM ranked_d7_all WHERE rank_best = 1 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去7日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 431
  FROM ranked_d7_all WHERE rank_best <= 3 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去7日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 432
  FROM ranked_d7_all WHERE rank_worst = 1 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去7日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 433
  FROM ranked_d7_all WHERE rank_worst <= 3 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去7日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 434
  FROM winrate_d7_all WHERE prev_d7_win_rate = 1.0 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去7日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 435
  FROM winrate_d7_all WHERE prev_d7_win_rate >= 0.6 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去7日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 436
  FROM winrate_d7_all WHERE prev_d7_win_rate <= 0.3 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去7日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 437
  FROM winrate_d7_all WHERE prev_d7_win_rate = 0 AND is_special_day = TRUE

  UNION ALL

  -- ========== 過去28日 ==========
  SELECT '特日', '過去28日', '差枚ベスト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 440
  FROM ranked_d28_all WHERE rank_best = 1 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去28日', '差枚ベスト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 441
  FROM ranked_d28_all WHERE rank_best <= 3 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去28日', '差枚ワースト1', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 442
  FROM ranked_d28_all WHERE rank_worst = 1 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去28日', '差枚ワースト3', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 443
  FROM ranked_d28_all WHERE rank_worst <= 3 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去28日', '勝率100%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 444
  FROM winrate_d28_all WHERE prev_d28_win_rate = 1.0 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去28日', '勝率60%以上', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 445
  FROM winrate_d28_all WHERE prev_d28_win_rate >= 0.6 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去28日', '勝率30%以下', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 446
  FROM winrate_d28_all WHERE prev_d28_win_rate <= 0.3 AND is_special_day = TRUE
  UNION ALL
  SELECT '特日', '過去28日', '勝率0%', COUNT(DISTINCT target_date), COUNT(*),
    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1),
    SUM(d1_diff), ROUND(AVG(d1_diff), 0),
    ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2), 447
  FROM winrate_d28_all WHERE prev_d28_win_rate = 0 AND is_special_day = TRUE
)
ORDER BY sort_order;
