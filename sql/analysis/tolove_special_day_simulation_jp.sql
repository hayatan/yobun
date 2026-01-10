-- ============================================================================
-- L+ToLOVEるダークネス 戦略シミュレーション（日本語版）
-- ============================================================================
-- 
-- 【分析目的】
--   アイランド秋葉原店の「L+ToLOVEるダークネス」において、
--   過去データに基づく台選び戦略がどの程度有効かをシミュレーションする。
--   様々な条件（曜日カテゴリ × 参照期間 × 戦略）の組み合わせで
--   期待値（機械割）や勝率を比較し、最適な立ち回りを見つける。
--
-- 【曜日カテゴリ】
--   - 全日: 全日付（曜日無考慮）
--   - 平日: 土日祝以外
--   - 土日祝: 土曜・日曜・祝日
--   - 特日: 0のつく日、1のつく日、6のつく日、月最終日
--
-- 【参照期間】
--   - 前日〜過去28日: 単一期間参照の基本戦略
--   - 複合: 長期(28日)と短期(3/5/7日)を組み合わせた複合戦略
--
-- 【戦略カテゴリ】
--   1. 差枚ベース: ベスト1/3、ワースト1/3
--   2. 勝率ベース: 100%、60%以上、30%以下、0%
--   3. 長期勝率ベース: 28日勝率50%以上/未満 × 短期勝率条件
--   4. 長期機械割ベース: 28日機械割110%/105%/100%未満 × 短期勝率条件
--
-- 【出力項目】
--   曜日, 参照期間, 戦略, 実施日数, 参照台数, 勝利日数, 勝率, 合計差枚, 平均差枚, 機械割
--
-- 【拡張方法（モジュラー設計）】
--   - 曜日カテゴリ追加: day_categories CTEに行を追加
--   - 長期条件追加: long_term_conditions CTEに行を追加
--   - 短期条件追加: short_term_conditions CTEに行を追加
--   → 組み合わせは自動生成されます
-- ============================================================================

WITH 
-- ============================================================================
-- 1. 基本データ（全期間のデータを横持ちで保持）
-- ============================================================================
base_data AS (
  SELECT
    target_date,
    machine_number,
    d1_diff,
    d1_game,
    -- 各期間の差枚
    prev_d1_diff,
    prev_d3_diff,
    prev_d5_diff,
    prev_d7_diff,
    prev_d28_diff,
    -- 各期間の勝率
    prev_d3_win_rate,
    prev_d5_win_rate,
    prev_d7_win_rate,
    prev_d28_win_rate,
    -- 過去28日の機械割
    prev_d28_payout_rate,
    -- 土日祝フラグ
    CASE 
      WHEN EXTRACT(DAYOFWEEK FROM target_date) IN (1, 7) THEN TRUE
      WHEN bqfunc.holidays_in_japan__us.holiday_name(target_date) IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS is_holiday,
    -- 特日フラグ
    CASE 
      WHEN EXTRACT(DAY FROM target_date) IN (10, 20, 30) THEN TRUE
      WHEN EXTRACT(DAY FROM target_date) IN (1, 11, 21, 31) THEN TRUE
      WHEN EXTRACT(DAY FROM target_date) IN (6, 16, 26) THEN TRUE
      WHEN target_date = LAST_DAY(target_date) THEN TRUE
      ELSE FALSE
    END AS is_special_day
  FROM `yobun-450512.datamart.machine_stats`
  WHERE hole = 'アイランド秋葉原店'
    AND machine = 'L+ToLOVEるダークネス'
    AND target_date >= DATE('2025-11-03')
    AND d1_diff IS NOT NULL
),

-- ============================================================================
-- 2. 曜日カテゴリ定義
-- ============================================================================
day_categories AS (
  SELECT '全日' AS `曜日`, 1 AS day_order, 'all' AS day_filter UNION ALL
  SELECT '平日', 2, 'weekday' UNION ALL
  SELECT '土日祝', 3, 'holiday' UNION ALL
  SELECT '特日', 4, 'special'
),

-- ============================================================================
-- 3. 基本戦略（単一期間参照）- 参照期間ごとにランキング計算
-- ============================================================================
basic_d1 AS (
  SELECT 
    '前日' AS `参照期間`, 1 AS period_order,
    target_date, machine_number, d1_diff, d1_game, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d1_diff DESC) AS rank_best,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d1_diff ASC) AS rank_worst,
    CAST(NULL AS FLOAT64) AS ref_win_rate
  FROM base_data WHERE prev_d1_diff IS NOT NULL
),
basic_d3 AS (
  SELECT 
    '過去3日', 2, target_date, machine_number, d1_diff, d1_game, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d3_diff DESC),
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d3_diff ASC),
    prev_d3_win_rate
  FROM base_data WHERE prev_d3_diff IS NOT NULL
),
basic_d5 AS (
  SELECT 
    '過去5日', 3, target_date, machine_number, d1_diff, d1_game, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d5_diff DESC),
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d5_diff ASC),
    prev_d5_win_rate
  FROM base_data WHERE prev_d5_diff IS NOT NULL
),
basic_d7 AS (
  SELECT 
    '過去7日', 4, target_date, machine_number, d1_diff, d1_game, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d7_diff DESC),
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d7_diff ASC),
    prev_d7_win_rate
  FROM base_data WHERE prev_d7_diff IS NOT NULL
),
basic_d28 AS (
  SELECT 
    '過去28日', 5, target_date, machine_number, d1_diff, d1_game, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d28_diff DESC),
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d28_diff ASC),
    prev_d28_win_rate
  FROM base_data WHERE prev_d28_diff IS NOT NULL
),

basic_periods AS (
  SELECT * FROM basic_d1 UNION ALL
  SELECT * FROM basic_d3 UNION ALL
  SELECT * FROM basic_d5 UNION ALL
  SELECT * FROM basic_d7 UNION ALL
  SELECT * FROM basic_d28
),

basic_with_strategies AS (
  SELECT 
    p.`参照期間`, p.period_order, p.target_date, p.d1_diff, p.d1_game, p.is_holiday, p.is_special_day,
    s.`戦略`, s.strategy_order
  FROM basic_periods p
  CROSS JOIN UNNEST([
    STRUCT('差枚ベスト1' AS `戦略`, 1 AS strategy_order, p.rank_best = 1 AS matches),
    STRUCT('差枚ベスト3', 2, p.rank_best <= 3),
    STRUCT('差枚ワースト1', 3, p.rank_worst = 1),
    STRUCT('差枚ワースト3', 4, p.rank_worst <= 3),
    STRUCT('勝率100%', 5, p.ref_win_rate IS NOT NULL AND p.ref_win_rate = 1.0),
    STRUCT('勝率60%以上', 6, p.ref_win_rate IS NOT NULL AND p.ref_win_rate >= 0.6),
    STRUCT('勝率30%以下', 7, p.ref_win_rate IS NOT NULL AND p.ref_win_rate <= 0.3),
    STRUCT('勝率0%', 8, p.ref_win_rate IS NOT NULL AND p.ref_win_rate = 0)
  ]) AS s
  WHERE s.matches = TRUE
),

-- ============================================================================
-- 4. 複合戦略用マスタ定義（モジュラー設計）
-- ============================================================================

-- 長期条件マスタ（過去28日間の条件）
-- 追加方法: 新しいSTRUCTを配列に追加するだけ
long_term_conditions AS (
  SELECT * FROM UNNEST([
    STRUCT(
      '過去28日間勝率50%以上' AS lt_name, 
      'win_rate' AS lt_type, 
      0.5 AS lt_threshold, 
      '>=' AS lt_op, 
      1 AS lt_sort
    ),
    STRUCT('過去28日間勝率50%未満', 'win_rate', 0.5, '<', 2),
    STRUCT('過去28日間機械割110%以上', 'payout_rate', 1.10, '>=', 3),
    STRUCT('過去28日間機械割105%以上', 'payout_rate', 1.05, '>=', 4),
    STRUCT('過去28日間機械割100%未満', 'payout_rate', 1.00, '<', 5)
  ])
),

-- 短期条件マスタ（過去3/5/7日間の条件）
-- 追加方法: 新しいSTRUCTを配列に追加するだけ
short_term_conditions AS (
  SELECT * FROM UNNEST([
    -- 条件なし（長期のみ）
    STRUCT(
      '' AS st_name, 
      0 AS st_period, 
      'none' AS st_type, 
      0.0 AS st_threshold, 
      '' AS st_op, 
      0 AS st_sort
    ),
    -- 過去3日間
    STRUCT('+過去3日間勝率100%', 3, 'win_rate', 1.0, '=', 1),
    STRUCT('+過去3日間勝率80%以上', 3, 'win_rate', 0.8, '>=', 2),
    STRUCT('+過去3日間勝率60%以上', 3, 'win_rate', 0.6, '>=', 3),
    STRUCT('+過去3日間勝率30%以下', 3, 'win_rate', 0.3, '<=', 4),
    STRUCT('+過去3日間勝率0%', 3, 'win_rate', 0.0, '=', 5),
    -- 過去5日間
    STRUCT('+過去5日間勝率100%', 5, 'win_rate', 1.0, '=', 11),
    STRUCT('+過去5日間勝率80%以上', 5, 'win_rate', 0.8, '>=', 12),
    STRUCT('+過去5日間勝率60%以上', 5, 'win_rate', 0.6, '>=', 13),
    STRUCT('+過去5日間勝率30%以下', 5, 'win_rate', 0.3, '<=', 14),
    STRUCT('+過去5日間勝率0%', 5, 'win_rate', 0.0, '=', 15),
    -- 過去7日間
    STRUCT('+過去7日間勝率100%', 7, 'win_rate', 1.0, '=', 21),
    STRUCT('+過去7日間勝率80%以上', 7, 'win_rate', 0.8, '>=', 22),
    STRUCT('+過去7日間勝率60%以上', 7, 'win_rate', 0.6, '>=', 23),
    STRUCT('+過去7日間勝率30%以下', 7, 'win_rate', 0.3, '<=', 24),
    STRUCT('+過去7日間勝率0%', 7, 'win_rate', 0.0, '=', 25)
  ])
),

-- ============================================================================
-- 5. 組み合わせ自動生成（CROSS JOIN）
-- ============================================================================
strategy_combinations AS (
  SELECT
    CONCAT(lt.lt_name, st.st_name) AS strategy_name,
    lt.lt_type, lt.lt_threshold, lt.lt_op,
    st.st_period, st.st_type, st.st_threshold, st.st_op,
    lt.lt_sort * 100 + st.st_sort AS sort_order
  FROM long_term_conditions lt
  CROSS JOIN short_term_conditions st
),

-- ============================================================================
-- 6. 動的条件評価
-- ============================================================================
compound_with_strategies AS (
  SELECT 
    '複合' AS `参照期間`, 
    99 AS period_order,
    b.target_date, b.d1_diff, b.d1_game, b.is_holiday, b.is_special_day,
    sc.strategy_name AS `戦略`, 
    sc.sort_order AS strategy_order
  FROM base_data b
  CROSS JOIN strategy_combinations sc
  WHERE 
    -- 長期条件の評価
    (
      (sc.lt_type = 'win_rate' AND (
        (sc.lt_op = '>=' AND b.prev_d28_win_rate >= sc.lt_threshold) OR
        (sc.lt_op = '<' AND b.prev_d28_win_rate < sc.lt_threshold)
      ))
      OR
      (sc.lt_type = 'payout_rate' AND (
        (sc.lt_op = '>=' AND b.prev_d28_payout_rate >= sc.lt_threshold) OR
        (sc.lt_op = '<' AND b.prev_d28_payout_rate < sc.lt_threshold)
      ))
    )
    AND
    -- 短期条件の評価
    (
      sc.st_type = 'none'
      OR
      (sc.st_period = 3 AND (
        (sc.st_op = '=' AND b.prev_d3_win_rate = sc.st_threshold) OR
        (sc.st_op = '>=' AND b.prev_d3_win_rate >= sc.st_threshold) OR
        (sc.st_op = '<=' AND b.prev_d3_win_rate <= sc.st_threshold)
      ))
      OR
      (sc.st_period = 5 AND (
        (sc.st_op = '=' AND b.prev_d5_win_rate = sc.st_threshold) OR
        (sc.st_op = '>=' AND b.prev_d5_win_rate >= sc.st_threshold) OR
        (sc.st_op = '<=' AND b.prev_d5_win_rate <= sc.st_threshold)
      ))
      OR
      (sc.st_period = 7 AND (
        (sc.st_op = '=' AND b.prev_d7_win_rate = sc.st_threshold) OR
        (sc.st_op = '>=' AND b.prev_d7_win_rate >= sc.st_threshold) OR
        (sc.st_op = '<=' AND b.prev_d7_win_rate <= sc.st_threshold)
      ))
    )
    AND b.prev_d28_win_rate IS NOT NULL
),

-- ============================================================================
-- 7. 全戦略の統合
-- ============================================================================
all_strategies AS (
  SELECT * FROM basic_with_strategies
  UNION ALL
  SELECT * FROM compound_with_strategies
),

-- ============================================================================
-- 8. 曜日カテゴリの適用
-- ============================================================================
categorized_data AS (
  SELECT 
    dc.`曜日`,
    dc.day_order,
    ast.`参照期間`,
    ast.period_order,
    ast.`戦略`,
    ast.strategy_order,
    ast.target_date,
    ast.d1_diff,
    ast.d1_game
  FROM all_strategies ast
  CROSS JOIN day_categories dc
  WHERE 
    (dc.day_filter = 'all') OR
    (dc.day_filter = 'weekday' AND ast.is_holiday = FALSE) OR
    (dc.day_filter = 'holiday' AND ast.is_holiday = TRUE) OR
    (dc.day_filter = 'special' AND ast.is_special_day = TRUE)
)

-- ============================================================================
-- 9. 最終集計
-- ============================================================================
SELECT
  `曜日`,
  `参照期間`,
  `戦略`,
  COUNT(DISTINCT target_date) AS `実施日数`,
  COUNT(*) AS `参照台数`,
  SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) AS `勝利日数`,
  ROUND(SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS `勝率`,
  SUM(d1_diff) AS `合計差枚`,
  ROUND(AVG(d1_diff), 0) AS `平均差枚`,
  ROUND((SUM(d1_game) * 3 + SUM(d1_diff)) / NULLIF(SUM(d1_game) * 3, 0) * 100, 2) AS `機械割`
FROM categorized_data
GROUP BY `曜日`, day_order, `参照期間`, period_order, `戦略`, strategy_order
ORDER BY day_order, period_order, strategy_order;
