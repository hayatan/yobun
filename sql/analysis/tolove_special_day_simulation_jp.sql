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
-- 【拡張方法】
--   - 曜日カテゴリ追加: day_categories CTEに行を追加
--   - 戦略追加: basic_strategies / compound_strategies のUNNEST配列に要素を追加
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
    -- 過去28日の機械割（データマートから取得）
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
-- 前日
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

-- 基本戦略の統合
basic_periods AS (
  SELECT * FROM basic_d1 UNION ALL
  SELECT * FROM basic_d3 UNION ALL
  SELECT * FROM basic_d5 UNION ALL
  SELECT * FROM basic_d7 UNION ALL
  SELECT * FROM basic_d28
),

-- 基本戦略の適用
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
-- 4. 複合戦略（長期28日 × 短期条件）
-- ============================================================================
compound_with_strategies AS (
  SELECT 
    '複合' AS `参照期間`, 
    99 AS period_order,
    b.target_date, b.d1_diff, b.d1_game, b.is_holiday, b.is_special_day,
    s.`戦略`, s.strategy_order
  FROM base_data b
  CROSS JOIN UNNEST([
    -- ========== 28日勝率50%以上 ==========
    STRUCT('過去28日間勝率50%以上' AS `戦略`, 101 AS strategy_order,
           b.prev_d28_win_rate >= 0.5 AS matches),
    STRUCT('過去28日間勝率50%以上+過去3日間勝率100%', 102,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d3_win_rate = 1.0),
    STRUCT('過去28日間勝率50%以上+過去5日間勝率100%', 103,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d5_win_rate = 1.0),
    STRUCT('過去28日間勝率50%以上+過去7日間勝率100%', 104,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d7_win_rate = 1.0),
    STRUCT('過去28日間勝率50%以上+過去3日間勝率80%以上', 105,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d3_win_rate >= 0.8),
    STRUCT('過去28日間勝率50%以上+過去5日間勝率80%以上', 106,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d5_win_rate >= 0.8),
    STRUCT('過去28日間勝率50%以上+過去7日間勝率80%以上', 107,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d7_win_rate >= 0.8),
    STRUCT('過去28日間勝率50%以上+過去3日間勝率60%以上', 108,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d3_win_rate >= 0.6),
    STRUCT('過去28日間勝率50%以上+過去5日間勝率60%以上', 109,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d5_win_rate >= 0.6),
    STRUCT('過去28日間勝率50%以上+過去7日間勝率60%以上', 110,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d7_win_rate >= 0.6),
    STRUCT('過去28日間勝率50%以上+過去3日間勝率30%以下', 111,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d3_win_rate <= 0.3),
    STRUCT('過去28日間勝率50%以上+過去5日間勝率30%以下', 112,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d5_win_rate <= 0.3),
    STRUCT('過去28日間勝率50%以上+過去7日間勝率30%以下', 113,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d7_win_rate <= 0.3),
    STRUCT('過去28日間勝率50%以上+過去3日間勝率0%', 114,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d3_win_rate = 0),
    STRUCT('過去28日間勝率50%以上+過去5日間勝率0%', 115,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d5_win_rate = 0),
    STRUCT('過去28日間勝率50%以上+過去7日間勝率0%', 116,
           b.prev_d28_win_rate >= 0.5 AND b.prev_d7_win_rate = 0),

    -- ========== 28日勝率50%未満 ==========
    STRUCT('過去28日間勝率50%以下', 201,
           b.prev_d28_win_rate < 0.5),
    STRUCT('過去28日間勝率50%以下+過去3日間勝率100%', 202,
           b.prev_d28_win_rate < 0.5 AND b.prev_d3_win_rate = 1.0),
    STRUCT('過去28日間勝率50%以下+過去5日間勝率100%', 203,
           b.prev_d28_win_rate < 0.5 AND b.prev_d5_win_rate = 1.0),
    STRUCT('過去28日間勝率50%以下+過去7日間勝率100%', 204,
           b.prev_d28_win_rate < 0.5 AND b.prev_d7_win_rate = 1.0),
    STRUCT('過去28日間勝率50%以下+過去3日間勝率80%以上', 205,
           b.prev_d28_win_rate < 0.5 AND b.prev_d3_win_rate >= 0.8),
    STRUCT('過去28日間勝率50%以下+過去5日間勝率80%以上', 206,
           b.prev_d28_win_rate < 0.5 AND b.prev_d5_win_rate >= 0.8),
    STRUCT('過去28日間勝率50%以下+過去7日間勝率80%以上', 207,
           b.prev_d28_win_rate < 0.5 AND b.prev_d7_win_rate >= 0.8),
    STRUCT('過去28日間勝率50%以下+過去3日間勝率60%以上', 208,
           b.prev_d28_win_rate < 0.5 AND b.prev_d3_win_rate >= 0.6),
    STRUCT('過去28日間勝率50%以下+過去5日間勝率60%以上', 209,
           b.prev_d28_win_rate < 0.5 AND b.prev_d5_win_rate >= 0.6),
    STRUCT('過去28日間勝率50%以下+過去7日間勝率60%以上', 210,
           b.prev_d28_win_rate < 0.5 AND b.prev_d7_win_rate >= 0.6),
    STRUCT('過去28日間勝率50%以下+過去3日間勝率30%以下', 211,
           b.prev_d28_win_rate < 0.5 AND b.prev_d3_win_rate <= 0.3),
    STRUCT('過去28日間勝率50%以下+過去5日間勝率30%以下', 212,
           b.prev_d28_win_rate < 0.5 AND b.prev_d5_win_rate <= 0.3),
    STRUCT('過去28日間勝率50%以下+過去7日間勝率30%以下', 213,
           b.prev_d28_win_rate < 0.5 AND b.prev_d7_win_rate <= 0.3),
    STRUCT('過去28日間勝率50%以下+過去3日間勝率0%', 214,
           b.prev_d28_win_rate < 0.5 AND b.prev_d3_win_rate = 0),
    STRUCT('過去28日間勝率50%以下+過去5日間勝率0%', 215,
           b.prev_d28_win_rate < 0.5 AND b.prev_d5_win_rate = 0),
    STRUCT('過去28日間勝率50%以下+過去7日間勝率0%', 216,
           b.prev_d28_win_rate < 0.5 AND b.prev_d7_win_rate = 0),

    -- ========== 28日機械割110%以上 ==========
    STRUCT('過去28日間機械割110%以上', 301,
           b.prev_d28_payout_rate >= 1.10),
    STRUCT('過去28日間機械割110%以上+過去3日間勝率100%', 302,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d3_win_rate = 1.0),
    STRUCT('過去28日間機械割110%以上+過去5日間勝率100%', 303,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d5_win_rate = 1.0),
    STRUCT('過去28日間機械割110%以上+過去7日間勝率100%', 304,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d7_win_rate = 1.0),
    STRUCT('過去28日間機械割110%以上+過去3日間勝率80%以上', 305,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d3_win_rate >= 0.8),
    STRUCT('過去28日間機械割110%以上+過去5日間勝率80%以上', 306,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d5_win_rate >= 0.8),
    STRUCT('過去28日間機械割110%以上+過去7日間勝率80%以上', 307,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d7_win_rate >= 0.8),
    STRUCT('過去28日間機械割110%以上+過去3日間勝率60%以上', 308,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d3_win_rate >= 0.6),
    STRUCT('過去28日間機械割110%以上+過去5日間勝率60%以上', 309,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d5_win_rate >= 0.6),
    STRUCT('過去28日間機械割110%以上+過去7日間勝率60%以上', 310,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d7_win_rate >= 0.6),
    STRUCT('過去28日間機械割110%以上+過去3日間勝率30%以下', 311,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d3_win_rate <= 0.3),
    STRUCT('過去28日間機械割110%以上+過去5日間勝率30%以下', 312,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d5_win_rate <= 0.3),
    STRUCT('過去28日間機械割110%以上+過去7日間勝率30%以下', 313,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d7_win_rate <= 0.3),
    STRUCT('過去28日間機械割110%以上+過去3日間勝率0%', 314,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d3_win_rate = 0),
    STRUCT('過去28日間機械割110%以上+過去5日間勝率0%', 315,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d5_win_rate = 0),
    STRUCT('過去28日間機械割110%以上+過去7日間勝率0%', 316,
           b.prev_d28_payout_rate >= 1.10 AND b.prev_d7_win_rate = 0),

    -- ========== 28日機械割105%以上 ==========
    STRUCT('過去28日間機械割105%以上', 401,
           b.prev_d28_payout_rate >= 1.05),
    STRUCT('過去28日間機械割105%以上+過去3日間勝率100%', 402,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d3_win_rate = 1.0),
    STRUCT('過去28日間機械割105%以上+過去5日間勝率100%', 403,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d5_win_rate = 1.0),
    STRUCT('過去28日間機械割105%以上+過去7日間勝率100%', 404,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d7_win_rate = 1.0),
    STRUCT('過去28日間機械割105%以上+過去3日間勝率80%以上', 405,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d3_win_rate >= 0.8),
    STRUCT('過去28日間機械割105%以上+過去5日間勝率80%以上', 406,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d5_win_rate >= 0.8),
    STRUCT('過去28日間機械割105%以上+過去7日間勝率80%以上', 407,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d7_win_rate >= 0.8),
    STRUCT('過去28日間機械割105%以上+過去3日間勝率60%以上', 408,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d3_win_rate >= 0.6),
    STRUCT('過去28日間機械割105%以上+過去5日間勝率60%以上', 409,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d5_win_rate >= 0.6),
    STRUCT('過去28日間機械割105%以上+過去7日間勝率60%以上', 410,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d7_win_rate >= 0.6),
    STRUCT('過去28日間機械割105%以上+過去3日間勝率30%以下', 411,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d3_win_rate <= 0.3),
    STRUCT('過去28日間機械割105%以上+過去5日間勝率30%以下', 412,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d5_win_rate <= 0.3),
    STRUCT('過去28日間機械割105%以上+過去7日間勝率30%以下', 413,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d7_win_rate <= 0.3),
    STRUCT('過去28日間機械割105%以上+過去3日間勝率0%', 414,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d3_win_rate = 0),
    STRUCT('過去28日間機械割105%以上+過去5日間勝率0%', 415,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d5_win_rate = 0),
    STRUCT('過去28日間機械割105%以上+過去7日間勝率0%', 416,
           b.prev_d28_payout_rate >= 1.05 AND b.prev_d7_win_rate = 0),

    -- ========== 28日機械割100%未満 ==========
    STRUCT('過去28日間機械割100%以下', 501,
           b.prev_d28_payout_rate < 1.00),
    STRUCT('過去28日間機械割100%以下+過去3日間勝率100%', 502,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d3_win_rate = 1.0),
    STRUCT('過去28日間機械割100%以下+過去5日間勝率100%', 503,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d5_win_rate = 1.0),
    STRUCT('過去28日間機械割100%以下+過去7日間勝率100%', 504,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d7_win_rate = 1.0),
    STRUCT('過去28日間機械割100%以下+過去3日間勝率80%以上', 505,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d3_win_rate >= 0.8),
    STRUCT('過去28日間機械割100%以下+過去5日間勝率80%以上', 506,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d5_win_rate >= 0.8),
    STRUCT('過去28日間機械割100%以下+過去7日間勝率80%以上', 507,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d7_win_rate >= 0.8),
    STRUCT('過去28日間機械割100%以下+過去3日間勝率60%以上', 508,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d3_win_rate >= 0.6),
    STRUCT('過去28日間機械割100%以下+過去5日間勝率60%以上', 509,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d5_win_rate >= 0.6),
    STRUCT('過去28日間機械割100%以下+過去7日間勝率60%以上', 510,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d7_win_rate >= 0.6),
    STRUCT('過去28日間機械割100%以下+過去3日間勝率30%以下', 511,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d3_win_rate <= 0.3),
    STRUCT('過去28日間機械割100%以下+過去5日間勝率30%以下', 512,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d5_win_rate <= 0.3),
    STRUCT('過去28日間機械割100%以下+過去7日間勝率30%以下', 513,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d7_win_rate <= 0.3),
    STRUCT('過去28日間機械割100%以下+過去3日間勝率0%', 514,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d3_win_rate = 0),
    STRUCT('過去28日間機械割100%以下+過去5日間勝率0%', 515,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d5_win_rate = 0),
    STRUCT('過去28日間機械割100%以下+過去7日間勝率0%', 516,
           b.prev_d28_payout_rate < 1.00 AND b.prev_d7_win_rate = 0)
  ]) AS s
  WHERE s.matches = TRUE
    AND b.prev_d28_win_rate IS NOT NULL
),

-- ============================================================================
-- 5. 全戦略の統合
-- ============================================================================
all_strategies AS (
  SELECT * FROM basic_with_strategies
  UNION ALL
  SELECT * FROM compound_with_strategies
),

-- ============================================================================
-- 6. 曜日カテゴリの適用
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
-- 7. 最終集計
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
