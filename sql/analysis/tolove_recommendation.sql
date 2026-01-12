-- ============================================================================
-- L+ToLOVEるダークネス 戦略シミュレーション + 台番推薦
-- ============================================================================
-- 
-- 【パラメータ定義】
--   以下のDECLARE文で定義した値を使用
--   target_dateがNULLの場合: 最新日の次の日（デフォルト動作）
-- ============================================================================
DECLARE target_date DATE DEFAULT NULL;  -- 推奨台を出す日付（NULL=最新日の次の日）
DECLARE target_hole STRING DEFAULT 'アイランド秋葉原店';  -- 対象店舗
DECLARE target_machine STRING DEFAULT 'L+ToLOVEるダークネス';  -- 対象機種

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
-- 【戦略の組み合わせロジック】
--   長期条件（6種類）: 条件なし、過去28日間勝率50%超/以下（2段階、短期条件との一貫性確保）、
--                     過去28日間機械割110%以上/105%以上110%未満/100%以上105%未満/100%未満（MECE）
--   短期条件（19種類）: 条件なし、勝率条件（18種類、MECE、6段階×3期間）、末尾関連性（5種類）
--   短期条件は「勝率条件」と「末尾関連性」のいずれか1つのみ（両方は不可）
--   組み合わせ数: 6 × 19 = 114種類
--
-- 【MECE化の理由】
--   条件が重複すると、同じ台が複数の戦略に重複してカウントされ、評価が不当に高くなる
--   範囲を細かく分割することで、各条件が独立し、正確な評価が可能
--   長期条件の勝率は「50%超/以下」とすることで、短期条件との一貫性を確保
--
-- 【勝率範囲の定義（短期条件、MECE、6段階）】
--   100%: 全勝（`>= 1.0 AND <= 1.0`）
--   75%超100%未満: ほとんど勝ち（`> 0.75 AND < 1.0`）
--   50%超75%以下: 中間やや勝ち（`> 0.5 AND <= 0.75`）
--   25%超50%以下: 中間やや負け（`> 0.25 AND <= 0.5`）
--   0%超25%未満: ほとんど負け（`> 0.0 AND < 0.25`）
--   0%: 全敗（`>= 0.0 AND <= 0.0`）
--
-- 【50%ちょうどの扱い（一貫性確保）】
--   長期「50%超」× 短期「ほとんど勝ち」: 両方とも`> 0.5`なので、50%ちょうどは除外される（一貫性あり）
--   長期「50%超」× 短期「中間やや勝ち」: 組み合わせると`> 0.5 AND <= 0.75`（一貫性あり）
--   長期「50%超」× 短期「中間やや負け」: 組み合わせると空集合になる（自然に除外される）
--   長期「50%以下」× 短期「中間やや負け」: 組み合わせると`> 0.25 AND <= 0.5`（50%ちょうどを含む、一貫性あり）
--
-- 【末尾関連性の判定ロジック】
--   台番末尾1桁=日付末尾1桁、台番末尾2桁=日付末尾2桁、台番末尾1桁=日付末尾1桁+1/-1
--
-- 【基本戦略と複合戦略の違い】
--   基本戦略: 末尾関連性を適用しない（サンプルサイズ確保）
--   複合戦略: 末尾関連性を含む全組み合わせを分析
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
-- Part 0: パラメータ・設定定義
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 0-1. 推奨台を出す日付の決定
-- ----------------------------------------------------------------------------
-- DECLAREで定義したtarget_dateを使用
-- target_dateがNULLの場合: 最新日の次の日（デフォルト動作）
-- ----------------------------------------------------------------------------
target_date_calc AS (
  SELECT 
    target_date AS final_target_date
),

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
    b.target_date,
    b.machine_number,
    -- 当日データ
    b.d1_diff,
    b.d1_game,
    -- 当日を含む各期間のデータ（台番算出用）
    b.d1_diff AS curr_d1_diff,
    b.d3_win_rate AS curr_d3_win_rate,
    b.d5_win_rate AS curr_d5_win_rate,
    b.d7_win_rate AS curr_d7_win_rate,
    b.d28_win_rate AS curr_d28_win_rate,
    b.d28_payout_rate AS curr_d28_payout_rate,
    -- 当日を含まない各期間のデータ（シミュレーション用）
    b.prev_d1_diff,
    b.prev_d3_diff,
    b.prev_d5_diff,
    b.prev_d7_diff,
    b.prev_d28_diff,
    b.prev_d3_win_rate,
    b.prev_d5_win_rate,
    b.prev_d7_win_rate,
    b.prev_d28_win_rate,
    b.prev_d28_payout_rate,
    -- 土日祝フラグ
    CASE 
      WHEN EXTRACT(DAYOFWEEK FROM b.target_date) IN (1, 7) THEN TRUE
      WHEN bqfunc.holidays_in_japan__us.holiday_name(b.target_date) IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS is_holiday
  FROM `yobun-450512.datamart.machine_stats` b
  WHERE b.hole = target_hole
    AND b.machine = target_machine
    AND b.target_date >= DATE('2025-11-03')
    AND b.d1_diff IS NOT NULL
),

-- ----------------------------------------------------------------------------
-- 1-2. 特日定義（店舗ごとに編集が必要な箇所）
-- ----------------------------------------------------------------------------
-- 【編集方法】
--   店舗によって特日の定義が異なる場合は、このCTEのCASE文を編集してください。
--   例: 別の店舗では「5のつく日」を追加する場合
--       WHEN EXTRACT(DAY FROM target_date) IN (5, 15, 25) THEN TRUE
--   を追加
-- 
-- 【現在の定義（アイランド秋葉原店用）】
--   - 0のつく日（10, 20, 30）
--   - 1のつく日（1, 11, 21, 31）
--   - 6のつく日（6, 16, 26）
--   - 月最終日
-- ============================================================================
special_day_logic AS (
  SELECT 
    target_date,
    CASE 
      WHEN EXTRACT(DAY FROM target_date) IN (10, 20, 30) THEN TRUE
      WHEN EXTRACT(DAY FROM target_date) IN (1, 11, 21, 31) THEN TRUE
      WHEN EXTRACT(DAY FROM target_date) IN (6, 16, 26) THEN TRUE
      WHEN target_date = LAST_DAY(target_date) THEN TRUE
      ELSE FALSE
    END AS is_special_day
  FROM base_data
  GROUP BY target_date
),

-- base_dataに特日フラグと末尾情報を追加
base_data_with_special AS (
  SELECT
    bd.*,
    COALESCE(sdl.is_special_day, FALSE) AS is_special_day,
    -- 末尾情報
    MOD(EXTRACT(DAY FROM bd.target_date), 10) AS date_last_1digit,
    EXTRACT(DAY FROM bd.target_date) AS date_last_2digits,
    MOD(bd.machine_number, 10) AS machine_last_1digit,
    MOD(bd.machine_number, 100) AS machine_last_2digits
  FROM base_data bd
  LEFT JOIN special_day_logic sdl ON bd.target_date = sdl.target_date
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
-- 【MECE対応】機械割の条件は排他的な範囲で定義
-- ----------------------------------------------------------------------------
long_term_conditions AS (
  SELECT * FROM UNNEST([
    STRUCT(
      '条件なし' AS lt_name,
      'none' AS lt_type,
      CAST(NULL AS FLOAT64) AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      CAST(NULL AS STRING) AS lt_op,
      0 AS lt_sort
    ),
    STRUCT(
      '過去28日間勝率50%超' AS lt_name,
      'win_rate' AS lt_type,
      0.5 AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      '>' AS lt_op,
      1 AS lt_sort
    ),
    STRUCT(
      '過去28日間勝率50%以下' AS lt_name,
      'win_rate' AS lt_type,
      0.5 AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      '<=' AS lt_op,
      2 AS lt_sort
    ),
    STRUCT(
      '過去28日間機械割110%以上' AS lt_name,
      'payout_rate' AS lt_type,
      1.10 AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      '>=' AS lt_op,
      3 AS lt_sort
    ),
    STRUCT(
      '過去28日間機械割105%以上110%未満' AS lt_name,
      'payout_rate' AS lt_type,
      1.05 AS lt_threshold,
      1.10 AS lt_threshold_upper,
      '>=' AS lt_op,
      4 AS lt_sort
    ),
    STRUCT(
      '過去28日間機械割100%以上105%未満' AS lt_name,
      'payout_rate' AS lt_type,
      1.00 AS lt_threshold,
      1.05 AS lt_threshold_upper,
      '>=' AS lt_op,
      5 AS lt_sort
    ),
    STRUCT(
      '過去28日間機械割100%未満' AS lt_name,
      'payout_rate' AS lt_type,
      1.00 AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      '<' AS lt_op,
      6 AS lt_sort
    )
  ])
),

-- ----------------------------------------------------------------------------
-- 1-4. 短期勝率条件マスタ（過去3/5/7日間の条件）
-- ----------------------------------------------------------------------------
-- 追加方法: 新しいSTRUCTを配列に追加するだけ
-- 【MECE対応】勝率の条件は排他的な範囲で定義
-- ----------------------------------------------------------------------------
short_term_win_rate_conditions AS (
  SELECT * FROM UNNEST([
    -- 条件なし
    STRUCT('' AS st_name, 0 AS st_period, 'none' AS st_type, 0.0 AS st_threshold, '' AS st_op, CAST(NULL AS FLOAT64) AS st_threshold_upper, 0 AS st_sort),
    -- 過去3日間（MECE、6段階）
    STRUCT('+過去3日間勝率100%', 3, 'win_rate', 1.0, '>=', 1.0, 1),
    STRUCT('+過去3日間勝率75%超100%未満', 3, 'win_rate', 0.75, '>', 1.0, 2),
    STRUCT('+過去3日間勝率50%超75%以下', 3, 'win_rate', 0.5, '>', 0.75, 3),
    STRUCT('+過去3日間勝率25%超50%以下', 3, 'win_rate', 0.25, '>', 0.5, 4),
    STRUCT('+過去3日間勝率0%超25%未満', 3, 'win_rate', 0.0, '>', 0.25, 5),
    STRUCT('+過去3日間勝率0%', 3, 'win_rate', 0.0, '>=', 0.0, 6),
    -- 過去5日間（同様に6段階）
    STRUCT('+過去5日間勝率100%', 5, 'win_rate', 1.0, '>=', 1.0, 11),
    STRUCT('+過去5日間勝率75%超100%未満', 5, 'win_rate', 0.75, '>', 1.0, 12),
    STRUCT('+過去5日間勝率50%超75%以下', 5, 'win_rate', 0.5, '>', 0.75, 13),
    STRUCT('+過去5日間勝率25%超50%以下', 5, 'win_rate', 0.25, '>', 0.5, 14),
    STRUCT('+過去5日間勝率0%超25%未満', 5, 'win_rate', 0.0, '>', 0.25, 15),
    STRUCT('+過去5日間勝率0%', 5, 'win_rate', 0.0, '>=', 0.0, 16),
    -- 過去7日間（同様に6段階）
    STRUCT('+過去7日間勝率100%', 7, 'win_rate', 1.0, '>=', 1.0, 21),
    STRUCT('+過去7日間勝率75%超100%未満', 7, 'win_rate', 0.75, '>', 1.0, 22),
    STRUCT('+過去7日間勝率50%超75%以下', 7, 'win_rate', 0.5, '>', 0.75, 23),
    STRUCT('+過去7日間勝率25%超50%以下', 7, 'win_rate', 0.25, '>', 0.5, 24),
    STRUCT('+過去7日間勝率0%超25%未満', 7, 'win_rate', 0.0, '>', 0.25, 25),
    STRUCT('+過去7日間勝率0%', 7, 'win_rate', 0.0, '>=', 0.0, 26)
  ])
),

-- ----------------------------------------------------------------------------
-- 1-5. 短期末尾関連性条件マスタ
-- ----------------------------------------------------------------------------
-- 追加方法: 新しいSTRUCTを配列に追加するだけ
-- ----------------------------------------------------------------------------
short_term_digit_conditions AS (
  SELECT * FROM UNNEST([
    -- 条件なし
    STRUCT('' AS st_name, 0 AS st_period, 'none' AS st_type, 0.0 AS st_threshold, '' AS st_op, CAST(NULL AS FLOAT64) AS st_threshold_upper, 0 AS st_sort),
    -- 末尾関連性条件
    STRUCT('+台番末尾1桁=日付末尾1桁', 0, 'digit_match_1', 0.0, '', CAST(NULL AS FLOAT64), 30),
    STRUCT('+台番末尾2桁=日付末尾2桁', 0, 'digit_match_2', 0.0, '', CAST(NULL AS FLOAT64), 31),
    STRUCT('+台番末尾1桁=日付末尾1桁+1', 0, 'digit_plus_1', 0.0, '', CAST(NULL AS FLOAT64), 32),
    STRUCT('+台番末尾1桁=日付末尾1桁-1', 0, 'digit_minus_1', 0.0, '', CAST(NULL AS FLOAT64), 33)
  ])
),

-- ----------------------------------------------------------------------------
-- 1-6. 短期条件の統合（条件なし、勝率条件、末尾関連性のいずれか1つ）
-- ----------------------------------------------------------------------------
short_term_conditions AS (
  SELECT * FROM short_term_win_rate_conditions
  UNION ALL
  SELECT * FROM short_term_digit_conditions
),

-- ----------------------------------------------------------------------------
-- 1-7. 戦略組み合わせ自動生成（CROSS JOIN）
-- ----------------------------------------------------------------------------
-- 長期条件 × 短期条件の組み合わせ
-- 短期条件は、勝率条件と末尾関連性が同時に選択されないように制御
-- ----------------------------------------------------------------------------
strategy_combinations AS (
  SELECT
    -- 戦略名の生成（空文字列の場合は「全条件なし」に置換）
    CASE 
      WHEN lt.lt_name = '条件なし' AND st.st_name = '' THEN '全条件なし'
      WHEN lt.lt_name = '条件なし' THEN st.st_name
      WHEN st.st_name = '' THEN lt.lt_name
      ELSE CONCAT(lt.lt_name, st.st_name)
    END AS strategy_name,
    lt.lt_type, lt.lt_threshold, lt.lt_threshold_upper, lt.lt_op,
    st.st_period, st.st_type, st.st_threshold, st.st_threshold_upper, st.st_op,
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
  FROM base_data_with_special WHERE prev_d1_diff IS NOT NULL
),
basic_d3 AS (
  SELECT 
    '過去3日', 2, target_date, machine_number, d1_diff, d1_game, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d3_diff DESC),
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d3_diff ASC),
    prev_d3_win_rate
  FROM base_data_with_special WHERE prev_d3_diff IS NOT NULL
),
basic_d5 AS (
  SELECT 
    '過去5日', 3, target_date, machine_number, d1_diff, d1_game, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d5_diff DESC),
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d5_diff ASC),
    prev_d5_win_rate
  FROM base_data_with_special WHERE prev_d5_diff IS NOT NULL
),
basic_d7 AS (
  SELECT 
    '過去7日', 4, target_date, machine_number, d1_diff, d1_game, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d7_diff DESC),
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d7_diff ASC),
    prev_d7_win_rate
  FROM base_data_with_special WHERE prev_d7_diff IS NOT NULL
),
basic_d28 AS (
  SELECT 
    '過去28日', 5, target_date, machine_number, d1_diff, d1_game, is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d28_diff DESC),
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d28_diff ASC),
    prev_d28_win_rate
  FROM base_data_with_special WHERE prev_d28_diff IS NOT NULL
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
  FROM base_data_with_special b
  CROSS JOIN strategy_combinations sc
  WHERE 
    -- 長期条件の評価
    (
      sc.lt_type = 'none'
      OR
      (sc.lt_type = 'win_rate' AND (
        (sc.lt_op = '>' AND b.prev_d28_win_rate > sc.lt_threshold) OR
        (sc.lt_op = '<=' AND b.prev_d28_win_rate <= sc.lt_threshold)
      ))
      OR
      (sc.lt_type = 'payout_rate' AND (
        (sc.lt_threshold_upper IS NULL AND (
          (sc.lt_op = '>=' AND b.prev_d28_payout_rate >= sc.lt_threshold) OR
          (sc.lt_op = '<' AND b.prev_d28_payout_rate < sc.lt_threshold)
        ))
        OR
        (sc.lt_threshold_upper IS NOT NULL AND 
         b.prev_d28_payout_rate >= sc.lt_threshold AND 
         b.prev_d28_payout_rate < sc.lt_threshold_upper)
      ))
    )
    AND
    -- 短期条件の評価
    (
      sc.st_type = 'none'
      OR
      (sc.st_type = 'win_rate' AND (
        (sc.st_threshold_upper IS NULL AND (
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
        ))
        OR
        (sc.st_threshold_upper IS NOT NULL AND (
          (sc.st_op = '>=' AND sc.st_period = 3 AND 
           b.prev_d3_win_rate >= sc.st_threshold AND 
           b.prev_d3_win_rate <= sc.st_threshold_upper)
          OR
          (sc.st_op = '>=' AND sc.st_period = 5 AND 
           b.prev_d5_win_rate >= sc.st_threshold AND 
           b.prev_d5_win_rate <= sc.st_threshold_upper)
          OR
          (sc.st_op = '>=' AND sc.st_period = 7 AND 
           b.prev_d7_win_rate >= sc.st_threshold AND 
           b.prev_d7_win_rate <= sc.st_threshold_upper)
          OR
          (sc.st_op = '>' AND sc.st_period = 3 AND 
           b.prev_d3_win_rate > sc.st_threshold AND 
           b.prev_d3_win_rate <= sc.st_threshold_upper)
          OR
          (sc.st_op = '>' AND sc.st_period = 5 AND 
           b.prev_d5_win_rate > sc.st_threshold AND 
           b.prev_d5_win_rate <= sc.st_threshold_upper)
          OR
          (sc.st_op = '>' AND sc.st_period = 7 AND 
           b.prev_d7_win_rate > sc.st_threshold AND 
           b.prev_d7_win_rate <= sc.st_threshold_upper)
        ))
      ))
      OR
      (sc.st_type = 'digit_match_1' AND b.machine_last_1digit = b.date_last_1digit)
      OR
      (sc.st_type = 'digit_match_2' AND b.machine_last_2digits = b.date_last_2digits)
      OR
      (sc.st_type = 'digit_plus_1' AND b.machine_last_1digit = MOD(b.date_last_1digit + 1, 10))
      OR
      (sc.st_type = 'digit_minus_1' AND b.machine_last_1digit = MOD(b.date_last_1digit - 1 + 10, 10))
    )
    AND (sc.lt_type = 'none' OR b.prev_d28_win_rate IS NOT NULL)
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
-- target_date_calcで指定された日付より前の最新データを取得
-- ----------------------------------------------------------------------------
latest_date AS (
  SELECT 
    COALESCE(
      (SELECT final_target_date - 1 FROM target_date_calc),
      MAX(target_date)
    ) AS max_date
  FROM base_data_with_special
  WHERE 
    (SELECT final_target_date FROM target_date_calc) IS NULL 
    OR target_date < (SELECT final_target_date FROM target_date_calc)
),

latest_data AS (
  SELECT b.*
  FROM base_data_with_special b
  INNER JOIN latest_date ld ON b.target_date = ld.max_date
),

-- ----------------------------------------------------------------------------
-- 3-2. 次の日の情報（日付、土日祝フラグ、特日フラグ）
-- ----------------------------------------------------------------------------
-- target_date_calcで指定された日付を使用、未指定時は最新日の次の日
-- 特日判定はspecial_day_logic（1-2）と同じロジックを使用
-- ----------------------------------------------------------------------------
next_day_info AS (
  SELECT 
    next_date,
    -- 次の日が土日祝か
    CASE 
      WHEN EXTRACT(DAYOFWEEK FROM next_date) IN (1, 7) THEN TRUE
      WHEN bqfunc.holidays_in_japan__us.holiday_name(next_date) IS NOT NULL THEN TRUE
      ELSE FALSE
    END AS next_is_holiday,
    -- 次の日が特日か（special_day_logic（1-2）と同じロジック）
    -- 編集が必要な場合は、special_day_logic（1-2）とこのCASE文の両方を編集してください
    CASE 
      WHEN EXTRACT(DAY FROM next_date) IN (10, 20, 30) THEN TRUE
      WHEN EXTRACT(DAY FROM next_date) IN (1, 11, 21, 31) THEN TRUE
      WHEN EXTRACT(DAY FROM next_date) IN (6, 16, 26) THEN TRUE
      WHEN next_date = LAST_DAY(next_date) THEN TRUE
      ELSE FALSE
    END AS next_is_special_day,
    -- 次の日の末尾情報
    MOD(EXTRACT(DAY FROM next_date), 10) AS next_date_last_1digit,
    EXTRACT(DAY FROM next_date) AS next_date_last_2digits
  FROM (
    SELECT 
      COALESCE(
        (SELECT final_target_date FROM target_date_calc),
        DATE_ADD(ld.max_date, INTERVAL 1 DAY)
      ) AS next_date
    FROM latest_date ld
    CROSS JOIN target_date_calc tdc
  )
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
  CROSS JOIN next_day_info ndi
  WHERE 
    -- 長期条件の評価（curr_d28_* を使用）
    (
      sc.lt_type = 'none'
      OR
      (sc.lt_type = 'win_rate' AND (
        (sc.lt_op = '>' AND ld.curr_d28_win_rate > sc.lt_threshold) OR
        (sc.lt_op = '<=' AND ld.curr_d28_win_rate <= sc.lt_threshold)
      ))
      OR
      (sc.lt_type = 'payout_rate' AND (
        (sc.lt_threshold_upper IS NULL AND (
          (sc.lt_op = '>=' AND ld.curr_d28_payout_rate >= sc.lt_threshold) OR
          (sc.lt_op = '<' AND ld.curr_d28_payout_rate < sc.lt_threshold)
        ))
        OR
        (sc.lt_threshold_upper IS NOT NULL AND 
         ld.curr_d28_payout_rate >= sc.lt_threshold AND 
         ld.curr_d28_payout_rate < sc.lt_threshold_upper)
      ))
    )
    AND
    -- 短期条件の評価（curr_d3/5/7_* を使用、末尾関連性はnext_dateを使用）
    (
      sc.st_type = 'none'
      OR
      (sc.st_type = 'win_rate' AND (
        (sc.st_threshold_upper IS NULL AND (
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
        ))
        OR
        (sc.st_threshold_upper IS NOT NULL AND (
          (sc.st_op = '>=' AND sc.st_period = 3 AND 
           ld.curr_d3_win_rate >= sc.st_threshold AND 
           ld.curr_d3_win_rate <= sc.st_threshold_upper)
          OR
          (sc.st_op = '>=' AND sc.st_period = 5 AND 
           ld.curr_d5_win_rate >= sc.st_threshold AND 
           ld.curr_d5_win_rate <= sc.st_threshold_upper)
          OR
          (sc.st_op = '>=' AND sc.st_period = 7 AND 
           ld.curr_d7_win_rate >= sc.st_threshold AND 
           ld.curr_d7_win_rate <= sc.st_threshold_upper)
          OR
          (sc.st_op = '>' AND sc.st_period = 3 AND 
           ld.curr_d3_win_rate > sc.st_threshold AND 
           ld.curr_d3_win_rate <= sc.st_threshold_upper)
          OR
          (sc.st_op = '>' AND sc.st_period = 5 AND 
           ld.curr_d5_win_rate > sc.st_threshold AND 
           ld.curr_d5_win_rate <= sc.st_threshold_upper)
          OR
          (sc.st_op = '>' AND sc.st_period = 7 AND 
           ld.curr_d7_win_rate > sc.st_threshold AND 
           ld.curr_d7_win_rate <= sc.st_threshold_upper)
        ))
      ))
      OR
      (sc.st_type = 'digit_match_1' AND ld.machine_last_1digit = ndi.next_date_last_1digit)
      OR
      (sc.st_type = 'digit_match_2' AND ld.machine_last_2digits = ndi.next_date_last_2digits)
      OR
      (sc.st_type = 'digit_plus_1' AND ld.machine_last_1digit = MOD(ndi.next_date_last_1digit + 1, 10))
      OR
      (sc.st_type = 'digit_minus_1' AND ld.machine_last_1digit = MOD(ndi.next_date_last_1digit - 1 + 10, 10))
    )
    AND (sc.lt_type = 'none' OR ld.curr_d28_win_rate IS NOT NULL)
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

