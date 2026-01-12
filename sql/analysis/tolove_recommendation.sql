-- ============================================================================
-- L+ToLOVEるダークネス 戦略シミュレーション + 台番推薦
-- ============================================================================
-- 
-- 【分析目的】
--   アイランド秋葉原店の「L+ToLOVEるダークネス」において、
--   過去データに基づく台選び戦略の有効性をシミュレーションし、
--   さらに次の日に打つべき台番を推薦する。
--
-- 【曜日カテゴリ】
--   - 全日: 全日付（曜日無考慮）
--   - 平日: 土日祝以外
--   - 土日祝: 土曜・日曜・祝日
--   - 特日: 0のつく日、1のつく日、6のつく日、月最終日
--
-- 【参照期間】
--   - 前日: 前日1日間のデータを参照
--   - 過去3日: 前日から3日間のデータを参照
--   - 過去5日: 前日から5日間のデータを参照
--   - 過去7日: 前日から7日間のデータを参照
--   - 過去28日: 前日から28日間のデータを参照
--   - 複合: 長期(28日)と短期(3/5/7日)を組み合わせた複合戦略
--
-- 【戦略カテゴリ】
--   1. 差枚ベース:
--      - 差枚ベスト1: 差枚1位の台を選ぶ
--      - 差枚ベスト3: 差枚上位3台を選ぶ
--      - 差枚ワースト1: 差枚最下位の台を選ぶ
--      - 差枚ワースト3: 差枚下位3台を選ぶ
--   2. 勝率ベース:
--      - 勝率100%: 全勝台を選ぶ
--      - 勝率60%以上: 勝率60%以上の台を選ぶ
--      - 勝率30%以下: 勝率30%以下の台を選ぶ
--      - 勝率0%: 全敗台を選ぶ
--   3. 長期勝率ベース（複合戦略）:
--      - 過去28日間勝率50%以上/未満 × 短期勝率条件（3/5/7日間の勝率100%、80%以上、60%以上、30%以下、0%）
--   4. 長期機械割ベース（複合戦略）:
--      - 過去28日間機械割110%/105%/100%未満 × 短期勝率条件（3/5/7日間の勝率100%、80%以上、60%以上、30%以下、0%）
--
-- 【出力項目】
--   シミュレーション結果:
--     曜日, 参照期間, 戦略, 実施日数, 参照台数, 勝利日数, 勝率, 合計差枚, 平均差枚, 機械割
--   台番推薦:
--     次の日, 該当台番
--
-- 【データ参照の違い】
--   シミュレーション（過去検証）: prev_d* カラム（当日を含まない過去データ）
--   次の日の台番算出: d* カラム（最新日を含む過去データ）
--
-- 【曜日カテゴリと台番出力の関係】
--   - 全日: 常に出力
--   - 平日: 次の日が平日の場合のみ出力
--   - 土日祝: 次の日が土日祝の場合のみ出力
--   - 特日: 次の日が特日の場合のみ出力
--
-- 【クエリ構造】
--   Part 1: 基本データ・マスタ定義
--   Part 2: シミュレーション（過去検証）
--   Part 3: 次の日の台番算出
--   Part 4: 最終出力
--
-- ============================================================================

WITH 
-- ############################################################################
-- Part 1: 基本データ・マスタ定義
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 1-1. 基本データ（全期間のデータを横持ちで保持）
-- ----------------------------------------------------------------------------
-- シミュレーション用: prev_d* カラム（当日を含まない）
-- 台番算出用: d* カラム（当日を含む）
-- ----------------------------------------------------------------------------
base_data AS (
  SELECT
    target_date,
    machine_number,
    -- 当日データ
    d1_diff,
    d1_game,
    -- 当日を含む各期間のデータ（台番算出用）
    d1_diff AS curr_d1_diff,
    d3_win_rate AS curr_d3_win_rate,
    d5_win_rate AS curr_d5_win_rate,
    d7_win_rate AS curr_d7_win_rate,
    d28_win_rate AS curr_d28_win_rate,
    d28_payout_rate AS curr_d28_payout_rate,
    -- 当日を含まない各期間のデータ（シミュレーション用）
    prev_d1_diff,
    prev_d3_diff,
    prev_d5_diff,
    prev_d7_diff,
    prev_d28_diff,
    prev_d3_win_rate,
    prev_d5_win_rate,
    prev_d7_win_rate,
    prev_d28_win_rate,
    prev_d28_payout_rate,
    -- 土日祝フラグ
    CASE 
      WHEN EXTRACT(DAYOFWEEK FROM target_date) IN (1, 7) THEN TRUE
      WHEN bqfunc.holidays_in_japan__us.holiday_name(target_date) IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS is_holiday,
    -- 特日フラグ（0/1/6のつく日、月最終日）
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

-- ----------------------------------------------------------------------------
-- 1-2. 曜日カテゴリ定義
-- ----------------------------------------------------------------------------
day_categories AS (
  SELECT '全日' AS `曜日`, 1 AS day_order, 'all' AS day_filter UNION ALL
  SELECT '平日', 2, 'weekday' UNION ALL
  SELECT '土日祝', 3, 'holiday' UNION ALL
  SELECT '特日', 4, 'special'
),

-- ----------------------------------------------------------------------------
-- 1-3. 長期条件マスタ（過去28日間の条件）
-- ----------------------------------------------------------------------------
-- 追加方法: 新しいSTRUCTを配列に追加するだけ
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- 1-4. 短期条件マスタ（過去3/5/7日間の条件）
-- ----------------------------------------------------------------------------
-- 追加方法: 新しいSTRUCTを配列に追加するだけ
-- ----------------------------------------------------------------------------
short_term_conditions AS (
  SELECT * FROM UNNEST([
    -- 条件なし（長期のみ）
    STRUCT('' AS st_name, 0 AS st_period, 'none' AS st_type, 0.0 AS st_threshold, '' AS st_op, 0 AS st_sort),
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

-- ----------------------------------------------------------------------------
-- 1-5. 戦略組み合わせ自動生成（CROSS JOIN）
-- ----------------------------------------------------------------------------
strategy_combinations AS (
  SELECT
    CONCAT(lt.lt_name, st.st_name) AS strategy_name,
    lt.lt_type, lt.lt_threshold, lt.lt_op,
    st.st_period, st.st_type, st.st_threshold, st.st_op,
    lt.lt_sort * 100 + st.st_sort AS sort_order
  FROM long_term_conditions lt
  CROSS JOIN short_term_conditions st
),

-- ############################################################################
-- Part 2: シミュレーション（過去検証）
-- ############################################################################
-- 目的: 各戦略が過去どの程度有効だったかを検証
-- 使用カラム: prev_d*（当日を含まない過去データ）
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 2-1. 基本戦略（単一期間参照）- 参照期間ごとにランキング計算
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- 2-2. 基本戦略の適用
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- 2-3. 複合戦略の動的条件評価
-- ----------------------------------------------------------------------------
-- prev_d* カラムを使用（当日を含まない）
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- 2-4. 全戦略の統合
-- ----------------------------------------------------------------------------
all_strategies AS (
  SELECT * FROM basic_with_strategies
  UNION ALL
  SELECT * FROM compound_with_strategies
),

-- ----------------------------------------------------------------------------
-- 2-5. 曜日カテゴリの適用・集計
-- ----------------------------------------------------------------------------
simulation_results AS (
  SELECT 
    dc.`曜日`,
    dc.day_order,
    dc.day_filter,
    ast.`参照期間`,
    ast.period_order,
    ast.`戦略`,
    ast.strategy_order,
    COUNT(DISTINCT ast.target_date) AS `実施日数`,
    COUNT(*) AS `参照台数`,
    SUM(CASE WHEN ast.d1_diff > 0 THEN 1 ELSE 0 END) AS `勝利日数`,
    ROUND(SUM(CASE WHEN ast.d1_diff > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS `勝率`,
    SUM(ast.d1_diff) AS `合計差枚`,
    ROUND(AVG(ast.d1_diff), 0) AS `平均差枚`,
    ROUND((SUM(ast.d1_game) * 3 + SUM(ast.d1_diff)) / NULLIF(SUM(ast.d1_game) * 3, 0) * 100, 2) AS `機械割`
  FROM all_strategies ast
  CROSS JOIN day_categories dc
  WHERE 
    (dc.day_filter = 'all') OR
    (dc.day_filter = 'weekday' AND ast.is_holiday = FALSE) OR
    (dc.day_filter = 'holiday' AND ast.is_holiday = TRUE) OR
    (dc.day_filter = 'special' AND ast.is_special_day = TRUE)
  GROUP BY dc.`曜日`, dc.day_order, dc.day_filter, ast.`参照期間`, ast.period_order, ast.`戦略`, ast.strategy_order
),

-- ############################################################################
-- Part 3: 次の日の台番算出
-- ############################################################################
-- 目的: 次の日に各戦略で打つべき台番を特定
-- 使用カラム: d*（最新日を含む過去データ）= curr_d* としてエイリアス
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 3-1. 最新日のデータ取得
-- ----------------------------------------------------------------------------
latest_date AS (
  SELECT MAX(target_date) AS max_date FROM base_data
),

latest_data AS (
  SELECT b.*
  FROM base_data b
  INNER JOIN latest_date ld ON b.target_date = ld.max_date
),

-- ----------------------------------------------------------------------------
-- 3-2. 次の日の情報（日付、土日祝フラグ、特日フラグ）
-- ----------------------------------------------------------------------------
next_day_info AS (
  SELECT 
    DATE_ADD(max_date, INTERVAL 1 DAY) AS next_date,
    -- 次の日が土日祝か
    CASE 
      WHEN EXTRACT(DAYOFWEEK FROM DATE_ADD(max_date, INTERVAL 1 DAY)) IN (1, 7) THEN TRUE
      WHEN bqfunc.holidays_in_japan__us.holiday_name(DATE_ADD(max_date, INTERVAL 1 DAY)) IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS next_is_holiday,
    -- 次の日が特日か
    CASE 
      WHEN EXTRACT(DAY FROM DATE_ADD(max_date, INTERVAL 1 DAY)) IN (10, 20, 30) THEN TRUE
      WHEN EXTRACT(DAY FROM DATE_ADD(max_date, INTERVAL 1 DAY)) IN (1, 11, 21, 31) THEN TRUE
      WHEN EXTRACT(DAY FROM DATE_ADD(max_date, INTERVAL 1 DAY)) IN (6, 16, 26) THEN TRUE
      WHEN DATE_ADD(max_date, INTERVAL 1 DAY) = LAST_DAY(DATE_ADD(max_date, INTERVAL 1 DAY)) THEN TRUE
      ELSE FALSE
    END AS next_is_special_day
  FROM latest_date
),

-- ----------------------------------------------------------------------------
-- 3-3. 基本戦略の該当台番（差枚ランキング、勝率条件）
-- ----------------------------------------------------------------------------
-- d* カラム（当日を含む）を使用
-- ----------------------------------------------------------------------------
next_basic_d1 AS (
  SELECT 
    '前日' AS `参照期間`, 1 AS period_order,
    machine_number,
    ROW_NUMBER() OVER (ORDER BY curr_d1_diff DESC) AS rank_best,
    ROW_NUMBER() OVER (ORDER BY curr_d1_diff ASC) AS rank_worst,
    CAST(NULL AS FLOAT64) AS ref_win_rate
  FROM latest_data WHERE curr_d1_diff IS NOT NULL
),
next_basic_d3 AS (
  SELECT '過去3日', 2, machine_number,
    ROW_NUMBER() OVER (ORDER BY curr_d1_diff + COALESCE(prev_d1_diff, 0) + COALESCE(prev_d3_diff - prev_d1_diff, 0) DESC),
    ROW_NUMBER() OVER (ORDER BY curr_d1_diff + COALESCE(prev_d1_diff, 0) + COALESCE(prev_d3_diff - prev_d1_diff, 0) ASC),
    curr_d3_win_rate
  FROM latest_data WHERE curr_d3_win_rate IS NOT NULL
),
next_basic_d5 AS (
  SELECT '過去5日', 3, machine_number,
    ROW_NUMBER() OVER (ORDER BY curr_d1_diff + COALESCE(prev_d1_diff, 0) DESC),
    ROW_NUMBER() OVER (ORDER BY curr_d1_diff + COALESCE(prev_d1_diff, 0) ASC),
    curr_d5_win_rate
  FROM latest_data WHERE curr_d5_win_rate IS NOT NULL
),
next_basic_d7 AS (
  SELECT '過去7日', 4, machine_number,
    ROW_NUMBER() OVER (ORDER BY curr_d1_diff + COALESCE(prev_d1_diff, 0) DESC),
    ROW_NUMBER() OVER (ORDER BY curr_d1_diff + COALESCE(prev_d1_diff, 0) ASC),
    curr_d7_win_rate
  FROM latest_data WHERE curr_d7_win_rate IS NOT NULL
),
next_basic_d28 AS (
  SELECT '過去28日', 5, machine_number,
    ROW_NUMBER() OVER (ORDER BY curr_d1_diff + COALESCE(prev_d1_diff, 0) DESC),
    ROW_NUMBER() OVER (ORDER BY curr_d1_diff + COALESCE(prev_d1_diff, 0) ASC),
    curr_d28_win_rate
  FROM latest_data WHERE curr_d28_win_rate IS NOT NULL
),

next_basic_periods AS (
  SELECT * FROM next_basic_d1 UNION ALL
  SELECT * FROM next_basic_d3 UNION ALL
  SELECT * FROM next_basic_d5 UNION ALL
  SELECT * FROM next_basic_d7 UNION ALL
  SELECT * FROM next_basic_d28
),

next_basic_machines AS (
  SELECT 
    p.`参照期間`,
    p.period_order,
    s.`戦略`,
    s.strategy_order,
    STRING_AGG(CAST(p.machine_number AS STRING), ', ' ORDER BY p.machine_number) AS target_machines
  FROM next_basic_periods p
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
  GROUP BY p.`参照期間`, p.period_order, s.`戦略`, s.strategy_order
),

-- ----------------------------------------------------------------------------
-- 3-4. 複合戦略の該当台番
-- ----------------------------------------------------------------------------
-- curr_d* カラム（当日を含む）を使用
-- ----------------------------------------------------------------------------
next_compound_machines AS (
  SELECT
    '複合' AS `参照期間`,
    99 AS period_order,
    sc.strategy_name AS `戦略`,
    sc.sort_order AS strategy_order,
    STRING_AGG(CAST(ld.machine_number AS STRING), ', ' ORDER BY ld.machine_number) AS target_machines
  FROM latest_data ld
  CROSS JOIN strategy_combinations sc
  WHERE 
    -- 長期条件の評価（curr_d28_* を使用）
    (
      (sc.lt_type = 'win_rate' AND (
        (sc.lt_op = '>=' AND ld.curr_d28_win_rate >= sc.lt_threshold) OR
        (sc.lt_op = '<' AND ld.curr_d28_win_rate < sc.lt_threshold)
      ))
      OR
      (sc.lt_type = 'payout_rate' AND (
        (sc.lt_op = '>=' AND ld.curr_d28_payout_rate >= sc.lt_threshold) OR
        (sc.lt_op = '<' AND ld.curr_d28_payout_rate < sc.lt_threshold)
      ))
    )
    AND
    -- 短期条件の評価（curr_d3/5/7_* を使用）
    (
      sc.st_type = 'none'
      OR
      (sc.st_period = 3 AND (
        (sc.st_op = '=' AND ld.curr_d3_win_rate = sc.st_threshold) OR
        (sc.st_op = '>=' AND ld.curr_d3_win_rate >= sc.st_threshold) OR
        (sc.st_op = '<=' AND ld.curr_d3_win_rate <= sc.st_threshold)
      ))
      OR
      (sc.st_period = 5 AND (
        (sc.st_op = '=' AND ld.curr_d5_win_rate = sc.st_threshold) OR
        (sc.st_op = '>=' AND ld.curr_d5_win_rate >= sc.st_threshold) OR
        (sc.st_op = '<=' AND ld.curr_d5_win_rate <= sc.st_threshold)
      ))
      OR
      (sc.st_period = 7 AND (
        (sc.st_op = '=' AND ld.curr_d7_win_rate = sc.st_threshold) OR
        (sc.st_op = '>=' AND ld.curr_d7_win_rate >= sc.st_threshold) OR
        (sc.st_op = '<=' AND ld.curr_d7_win_rate <= sc.st_threshold)
      ))
    )
    AND ld.curr_d28_win_rate IS NOT NULL
  GROUP BY sc.strategy_name, sc.sort_order
),

-- ----------------------------------------------------------------------------
-- 3-5. 全戦略の該当台番統合
-- ----------------------------------------------------------------------------
next_all_machines AS (
  SELECT * FROM next_basic_machines
  UNION ALL
  SELECT * FROM next_compound_machines
)

-- ############################################################################
-- Part 4: 最終出力
-- ############################################################################
SELECT
  -- シミュレーション結果
  sr.`曜日`,
  sr.`参照期間`,
  sr.`戦略`,
  sr.`実施日数`,
  sr.`参照台数`,
  sr.`勝利日数`,
  sr.`勝率`,
  sr.`合計差枚`,
  sr.`平均差枚`,
  sr.`機械割`,
  -- 次の日の情報
  ndi.next_date AS `次の日`,
  -- 該当台番（曜日カテゴリと次の日のカテゴリが一致する場合のみ出力）
  CASE 
    WHEN sr.day_filter = 'all' THEN nam.target_machines
    WHEN sr.day_filter = 'weekday' AND ndi.next_is_holiday = FALSE THEN nam.target_machines
    WHEN sr.day_filter = 'holiday' AND ndi.next_is_holiday = TRUE THEN nam.target_machines
    WHEN sr.day_filter = 'special' AND ndi.next_is_special_day = TRUE THEN nam.target_machines
    ELSE NULL
  END AS `該当台番`
FROM simulation_results sr
CROSS JOIN next_day_info ndi
LEFT JOIN next_all_machines nam 
  ON sr.`参照期間` = nam.`参照期間` 
  AND sr.`戦略` = nam.`戦略`
ORDER BY sr.day_order, sr.period_order, sr.strategy_order;

