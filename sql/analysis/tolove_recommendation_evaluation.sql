-- ============================================================================
-- 狙い台選定方法の評価クエリ
-- ============================================================================
-- 
-- 【分析目的】
--   過去の各日付で、`tolove_recommendation.sql` と `tolove_recommendation.gs` の
--   ロジックを使って「狙い台一覧」を生成し、TOP1/TOP3/TOP5/OUTLIERの台に座っていた場合の
--   実際のパフォーマンス（勝率・合計差枚・機械割・最大差枚・最低差枚）を評価する。
--
-- 【評価カテゴリ】
--   - TOP1: スコア1位の台のみ
--   - TOP3: スコア上位3台
--   - TOP5: スコア上位5台
--   - OUTLIER: 飛び抜けて高いスコアの台（日によって台数が変動）
--
-- 【OUTLIER（外れ値）の検出方法】
--   各評価日のスコア分布から、以下の閾値を計算:
--     閾値 = MIN(Q3 + 1.0*IQR, 平均 + 1.5*標準偏差)
--   この閾値以上のスコアを持つ台を「飛び抜けて高い」と判定
--   ※ IQR = Q3 - Q1（四分位範囲）
--
-- 【パラメータ定義】
-- ============================================================================
-- 対象店舗・機種を変更する場合は、以下のparams CTEの値を変更してください
-- ============================================================================
-- 注: DECLARE文はBigQuery Connectorでサポートされないため、params CTEを使用
-- 注: 診断機能はクエリの複雑さを減らすため一時的に無効化
-- score_methodはscore_methods CTEで一括定義（全手法を同時評価）
-- 
-- 【score_method一覧】
-- 'original': 元の計算方法（RMS × 信頼性 × 頻度 × 異常値 × 複合）
-- 'simple': 改善案1: RMSのみ
-- 'rms_reliability': 改善案2: RMS × 信頼性（絶対閾値ベース）
-- 'rms_frequency': 改善案3: RMS × 頻度ボーナス
-- 'strategy_filter': 改善案3b: 有効性スコア0.5以上の戦略のみ使用
-- 'rms_frequency_filter': ハイブリッド案1: RMS × 頻度 + 戦略フィルタ
-- 'rms_frequency_anomaly': ハイブリッド案2: RMS × 頻度 × 異常値ボーナス
-- 'rms_frequency_dual': ハイブリッド案3: RMS × 頻度 × 複合ボーナス
-- 'threshold': 改善案4: スコア閾値選別（TOP1の80%以上）

-- 【パーセンタイル閾値（GASと同じ値）】
-- ============================================================================
-- 勝率（過去28日間）:
--   - P25: 0.357（下位25%）
--   - P50: 0.429（中央値）
--   - P75: 0.50（上位25%）
-- 
-- 機械割（過去28日間）:
--   - P25: 1.0091（下位25%）
--   - P50: 1.0247（中央値）
--   - P75: 1.0447（上位25%）
-- ============================================================================

WITH 
-- ############################################################################
-- Part 0: パラメータ定義
-- ############################################################################
params AS (
  SELECT
    'アイランド秋葉原店' AS target_hole,      -- 対象店舗
    'L+ToLOVEるダークネス' AS target_machine, -- 対象機種
    120 AS evaluation_days                    -- 評価期間（直近N日間、推奨: 120日以上）
),

-- ############################################################################
-- Part 0b: 評価対象日付のリスト
-- ############################################################################
evaluation_dates AS (
  SELECT 
    ms.target_date AS data_date,  -- データ取得日（推奨台算出に使うデータの日付）
    -- 次の日（評価対象日 = 推奨台を出す日）
    DATE_ADD(ms.target_date, INTERVAL 1 DAY) AS evaluation_date
  FROM `yobun-450512.datamart.machine_stats` ms
  CROSS JOIN params p
  WHERE ms.hole = p.target_hole
    AND ms.machine = p.target_machine
    AND ms.target_date >= DATE('2025-11-03')
    AND ms.d1_diff IS NOT NULL
  GROUP BY ms.target_date
  HAVING ms.target_date >= DATE_SUB(CURRENT_DATE(), INTERVAL (SELECT evaluation_days FROM params) DAY)
),

-- ############################################################################
-- Part 1: 基本データ・マスタ定義（tolove_recommendation.sqlと同じ）
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 1-1. 基本データ
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
    b.d28_diff AS curr_d28_diff,
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
-- 1-2. 特日定義
-- ----------------------------------------------------------------------------
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

base_data_with_special AS (
  SELECT
    bd.*,
    COALESCE(sdl.is_special_day, FALSE) AS is_special_day,
    -- 末尾情報
    MOD(EXTRACT(DAY FROM bd.target_date), 10) AS date_last_1digit,
    EXTRACT(DAY FROM bd.target_date) AS date_last_2digits,
    MOD(bd.machine_number, 10) AS machine_last_1digit,
    MOD(bd.machine_number, 100) AS machine_last_2digits,
    -- 過去28日間の差枚ランキング
    ROW_NUMBER() OVER (PARTITION BY bd.target_date ORDER BY bd.prev_d28_diff DESC) AS prev_d28_rank_best,
    ROW_NUMBER() OVER (PARTITION BY bd.target_date ORDER BY bd.prev_d28_diff ASC) AS prev_d28_rank_worst
  FROM base_data bd
  LEFT JOIN special_day_logic sdl ON bd.target_date = sdl.target_date
),

-- ----------------------------------------------------------------------------
-- 1-3. 長期条件マスタ（tolove_recommendation.sqlと同じ）
-- ----------------------------------------------------------------------------
long_term_conditions AS (
  SELECT * FROM UNNEST([
    STRUCT(
      '条件なし' AS lt_name,
      'none' AS lt_type,
      CAST(NULL AS FLOAT64) AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      CAST(NULL AS STRING) AS lt_op,
      CAST(NULL AS STRING) AS lt_rank_type,
      CAST(NULL AS STRING) AS lt_rank_range,
      0 AS lt_sort
    ),
    STRUCT('過去28日間勝率50.0%以上' AS lt_name, 'win_rate' AS lt_type, 0.50 AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, '>=' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 1 AS lt_sort),
    STRUCT('過去28日間勝率42.9%以上50.0%未満' AS lt_name, 'win_rate' AS lt_type, 0.429 AS lt_threshold, 0.50 AS lt_threshold_upper, '>=' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 2 AS lt_sort),
    STRUCT('過去28日間勝率35.7%以上42.9%未満' AS lt_name, 'win_rate' AS lt_type, 0.357 AS lt_threshold, 0.429 AS lt_threshold_upper, '>=' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 3 AS lt_sort),
    STRUCT('過去28日間勝率35.7%未満' AS lt_name, 'win_rate' AS lt_type, 0.357 AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, '<' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 4 AS lt_sort),
    STRUCT('過去28日間機械割104.47%以上' AS lt_name, 'payout_rate' AS lt_type, 1.0447 AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, '>=' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 7 AS lt_sort),
    STRUCT('過去28日間機械割102.47%以上104.47%未満' AS lt_name, 'payout_rate' AS lt_type, 1.0247 AS lt_threshold, 1.0447 AS lt_threshold_upper, '>=' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 8 AS lt_sort),
    STRUCT('過去28日間機械割100.91%以上102.47%未満' AS lt_name, 'payout_rate' AS lt_type, 1.0091 AS lt_threshold, 1.0247 AS lt_threshold_upper, '>=' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 9 AS lt_sort),
    STRUCT('過去28日間機械割100.91%未満' AS lt_name, 'payout_rate' AS lt_type, 1.0091 AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, '<' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 10 AS lt_sort),
    STRUCT('過去28日間差枚ベスト1~5' AS lt_name, 'diff_rank' AS lt_type, CAST(NULL AS FLOAT64) AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, CAST(NULL AS STRING) AS lt_op, 'best' AS lt_rank_type, '1-5' AS lt_rank_range, 11 AS lt_sort),
    STRUCT('過去28日間差枚ベスト6~10' AS lt_name, 'diff_rank' AS lt_type, CAST(NULL AS FLOAT64) AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, CAST(NULL AS STRING) AS lt_op, 'best' AS lt_rank_type, '6-10' AS lt_rank_range, 12 AS lt_sort),
    STRUCT('過去28日間差枚ワースト1~5' AS lt_name, 'diff_rank' AS lt_type, CAST(NULL AS FLOAT64) AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, CAST(NULL AS STRING) AS lt_op, 'worst' AS lt_rank_type, '1-5' AS lt_rank_range, 13 AS lt_sort),
    STRUCT('過去28日間差枚ワースト6~10' AS lt_name, 'diff_rank' AS lt_type, CAST(NULL AS FLOAT64) AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, CAST(NULL AS STRING) AS lt_op, 'worst' AS lt_rank_type, '6-10' AS lt_rank_range, 14 AS lt_sort)
  ])
),

-- ----------------------------------------------------------------------------
-- 1-4. 短期条件マスタ（tolove_recommendation.sqlと同じ）
-- ----------------------------------------------------------------------------
short_term_win_rate_conditions AS (
  SELECT * FROM UNNEST([
    STRUCT('' AS st_name, 0 AS st_period, 'none' AS st_type, 0.0 AS st_threshold, '' AS st_op, CAST(NULL AS FLOAT64) AS st_threshold_upper, 0 AS st_sort),
    STRUCT('+過去3日間勝率100%', 3, 'win_rate', 1.0, '>=', 1.0, 1),
    STRUCT('+過去3日間勝率75%超100%未満', 3, 'win_rate', 0.75, '>', 1.0, 2),
    STRUCT('+過去3日間勝率50%超75%以下', 3, 'win_rate', 0.5, '>', 0.75, 3),
    STRUCT('+過去3日間勝率25%超50%以下', 3, 'win_rate', 0.25, '>', 0.5, 4),
    STRUCT('+過去3日間勝率0%超25%未満', 3, 'win_rate', 0.0, '>', 0.25, 5),
    STRUCT('+過去3日間勝率0%', 3, 'win_rate', 0.0, '>=', 0.0, 6),
    STRUCT('+過去5日間勝率100%', 5, 'win_rate', 1.0, '>=', 1.0, 11),
    STRUCT('+過去5日間勝率75%超100%未満', 5, 'win_rate', 0.75, '>', 1.0, 12),
    STRUCT('+過去5日間勝率50%超75%以下', 5, 'win_rate', 0.5, '>', 0.75, 13),
    STRUCT('+過去5日間勝率25%超50%以下', 5, 'win_rate', 0.25, '>', 0.5, 14),
    STRUCT('+過去5日間勝率0%超25%未満', 5, 'win_rate', 0.0, '>', 0.25, 15),
    STRUCT('+過去5日間勝率0%', 5, 'win_rate', 0.0, '>=', 0.0, 16),
    STRUCT('+過去7日間勝率100%', 7, 'win_rate', 1.0, '>=', 1.0, 21),
    STRUCT('+過去7日間勝率75%超100%未満', 7, 'win_rate', 0.75, '>', 1.0, 22),
    STRUCT('+過去7日間勝率50%超75%以下', 7, 'win_rate', 0.5, '>', 0.75, 23),
    STRUCT('+過去7日間勝率25%超50%以下', 7, 'win_rate', 0.25, '>', 0.5, 24),
    STRUCT('+過去7日間勝率0%超25%未満', 7, 'win_rate', 0.0, '>', 0.25, 25),
    STRUCT('+過去7日間勝率0%', 7, 'win_rate', 0.0, '>=', 0.0, 26)
  ])
),

short_term_digit_conditions AS (
  SELECT * FROM UNNEST([
    STRUCT('' AS st_name, 0 AS st_period, 'none' AS st_type, 0.0 AS st_threshold, '' AS st_op, CAST(NULL AS FLOAT64) AS st_threshold_upper, 0 AS st_sort),
    STRUCT('+台番末尾1桁=日付末尾1桁', 0, 'digit_match_1', 0.0, '', CAST(NULL AS FLOAT64), 30),
    STRUCT('+台番末尾2桁=日付末尾2桁', 0, 'digit_match_2', 0.0, '', CAST(NULL AS FLOAT64), 31),
    STRUCT('+台番末尾1桁=日付末尾1桁+1', 0, 'digit_plus_1', 0.0, '', CAST(NULL AS FLOAT64), 32),
    STRUCT('+台番末尾1桁=日付末尾1桁-1', 0, 'digit_minus_1', 0.0, '', CAST(NULL AS FLOAT64), 33)
  ])
),

short_term_conditions AS (
  SELECT * FROM short_term_win_rate_conditions
  UNION ALL
  SELECT * FROM short_term_digit_conditions
),

strategy_combinations AS (
  SELECT
    CASE 
      WHEN lt.lt_name = '条件なし' AND st.st_name = '' THEN '全条件なし'
      WHEN lt.lt_name = '条件なし' THEN st.st_name
      WHEN st.st_name = '' THEN lt.lt_name
      ELSE CONCAT(lt.lt_name, st.st_name)
    END AS strategy_name,
    lt.lt_type, lt.lt_threshold, lt.lt_threshold_upper, lt.lt_op,
    lt.lt_rank_type, lt.lt_rank_range,
    st.st_period, st.st_type, st.st_threshold, st.st_threshold_upper, st.st_op,
    lt.lt_sort * 100 + st.st_sort AS sort_order
  FROM long_term_conditions lt
  CROSS JOIN short_term_conditions st
),

-- ############################################################################
-- Part 2: 過去の各日付で推奨台を算出
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 2-1. 各評価日付について、推奨台を算出
-- ----------------------------------------------------------------------------
-- 各評価日付について、その日の前日データを使って推奨台を算出
-- ----------------------------------------------------------------------------
evaluation_base_data AS (
  SELECT
    ed.evaluation_date,  -- 評価対象日（推奨台を出す日）
    bd.target_date AS data_date,  -- データ取得日（推奨台算出に使うデータの日付）
    bd.machine_number,
    -- 当日を含む各期間のデータ（台番算出用）
    bd.curr_d1_diff,
    bd.curr_d3_win_rate,
    bd.curr_d5_win_rate,
    bd.curr_d7_win_rate,
    bd.curr_d28_diff,
    bd.curr_d28_win_rate,
    bd.curr_d28_payout_rate,
    -- 過去28日間の差枚ランキング
    ROW_NUMBER() OVER (PARTITION BY ed.evaluation_date ORDER BY bd.curr_d28_diff DESC) AS curr_d28_rank_best,
    ROW_NUMBER() OVER (PARTITION BY ed.evaluation_date ORDER BY bd.curr_d28_diff ASC) AS curr_d28_rank_worst,
    -- 評価対象日の末尾情報
    MOD(EXTRACT(DAY FROM ed.evaluation_date), 10) AS next_date_last_1digit,
    EXTRACT(DAY FROM ed.evaluation_date) AS next_date_last_2digits,
    bd.machine_last_1digit,
    bd.machine_last_2digits
  FROM evaluation_dates ed
  INNER JOIN base_data_with_special bd ON bd.target_date = ed.data_date
),

-- ----------------------------------------------------------------------------
-- 2-2. 複合戦略の該当台番（各評価日付について）
-- ----------------------------------------------------------------------------
evaluation_compound_machines AS (
  SELECT
    ebd.evaluation_date,
    ebd.machine_number,
    sc.strategy_name,
    sc.sort_order,
    -- 戦略の情報（スコア計算用）
    sc.lt_type, sc.lt_threshold, sc.lt_threshold_upper, sc.lt_op,
    sc.lt_rank_type, sc.lt_rank_range,
    sc.st_period, sc.st_type, sc.st_threshold, sc.st_threshold_upper, sc.st_op
  FROM evaluation_base_data ebd
  CROSS JOIN strategy_combinations sc
  WHERE 
    -- 長期条件の評価
    (
      sc.lt_type = 'none'
      OR
      (sc.lt_type = 'win_rate' AND ebd.curr_d28_win_rate IS NOT NULL AND (
        (sc.lt_threshold_upper IS NULL AND (
          (sc.lt_op = '>=' AND ebd.curr_d28_win_rate >= sc.lt_threshold) OR
          (sc.lt_op = '<' AND ebd.curr_d28_win_rate < sc.lt_threshold)
        ))
        OR
        (sc.lt_threshold_upper IS NOT NULL AND (
          (sc.lt_op = '>=' AND ebd.curr_d28_win_rate >= sc.lt_threshold AND ebd.curr_d28_win_rate <= sc.lt_threshold_upper)
        ))
      ))
      OR
      (sc.lt_type = 'payout_rate' AND (
        (sc.lt_threshold_upper IS NULL AND (
          (sc.lt_op = '>=' AND ebd.curr_d28_payout_rate >= sc.lt_threshold) OR
          (sc.lt_op = '<' AND ebd.curr_d28_payout_rate < sc.lt_threshold)
        ))
        OR
        (sc.lt_threshold_upper IS NOT NULL AND 
         ebd.curr_d28_payout_rate >= sc.lt_threshold AND 
         ebd.curr_d28_payout_rate < sc.lt_threshold_upper)
      ))
      OR
      (sc.lt_type = 'diff_rank' AND (
        (sc.lt_rank_type = 'best' AND (
          (sc.lt_rank_range = '1-5' AND ebd.curr_d28_rank_best BETWEEN 1 AND 5) OR
          (sc.lt_rank_range = '6-10' AND ebd.curr_d28_rank_best BETWEEN 6 AND 10)
        ))
        OR
        (sc.lt_rank_type = 'worst' AND (
          (sc.lt_rank_range = '1-5' AND ebd.curr_d28_rank_worst BETWEEN 1 AND 5) OR
          (sc.lt_rank_range = '6-10' AND ebd.curr_d28_rank_worst BETWEEN 6 AND 10)
        ))
      ))
    )
    AND
    -- 短期条件の評価
    (
      sc.st_type = 'none'
      OR
      (sc.st_type = 'win_rate' AND (
        CASE sc.st_period
          WHEN 3 THEN ebd.curr_d3_win_rate
          WHEN 5 THEN ebd.curr_d5_win_rate
          WHEN 7 THEN ebd.curr_d7_win_rate
          ELSE NULL
        END IS NOT NULL AND (
          (sc.st_threshold_upper IS NULL AND (
            (sc.st_op = '>=' AND CASE sc.st_period WHEN 3 THEN ebd.curr_d3_win_rate WHEN 5 THEN ebd.curr_d5_win_rate WHEN 7 THEN ebd.curr_d7_win_rate END >= sc.st_threshold) OR
            (sc.st_op = '>=' AND CASE sc.st_period WHEN 3 THEN ebd.curr_d3_win_rate WHEN 5 THEN ebd.curr_d5_win_rate WHEN 7 THEN ebd.curr_d7_win_rate END = sc.st_threshold)
          ))
          OR
          (sc.st_threshold_upper IS NOT NULL AND (
            (sc.st_op = '>=' AND CASE sc.st_period WHEN 3 THEN ebd.curr_d3_win_rate WHEN 5 THEN ebd.curr_d5_win_rate WHEN 7 THEN ebd.curr_d7_win_rate END >= sc.st_threshold AND CASE sc.st_period WHEN 3 THEN ebd.curr_d3_win_rate WHEN 5 THEN ebd.curr_d5_win_rate WHEN 7 THEN ebd.curr_d7_win_rate END <= sc.st_threshold_upper) OR
            (sc.st_op = '>' AND CASE sc.st_period WHEN 3 THEN ebd.curr_d3_win_rate WHEN 5 THEN ebd.curr_d5_win_rate WHEN 7 THEN ebd.curr_d7_win_rate END > sc.st_threshold AND CASE sc.st_period WHEN 3 THEN ebd.curr_d3_win_rate WHEN 5 THEN ebd.curr_d5_win_rate WHEN 7 THEN ebd.curr_d7_win_rate END <= sc.st_threshold_upper)
          ))
        )
      ))
      OR
      (sc.st_type = 'digit_match_1' AND ebd.machine_last_1digit = ebd.next_date_last_1digit)
      OR
      (sc.st_type = 'digit_match_2' AND ebd.machine_last_2digits = ebd.next_date_last_2digits)
      OR
      (sc.st_type = 'digit_plus_1' AND ebd.machine_last_1digit = MOD(ebd.next_date_last_1digit + 1, 10))
      OR
      (sc.st_type = 'digit_minus_1' AND ebd.machine_last_1digit = MOD(ebd.next_date_last_1digit - 1 + 10, 10))
    )
),

-- ############################################################################
-- Part 3: 各戦略のシミュレーション結果と有効性スコア計算
-- ############################################################################
-- 各評価日付の時点での過去データから計算する（未来の情報を使わない）
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- 3-1. 各評価日付ごとのシミュレーションベースデータ
-- ----------------------------------------------------------------------------
-- 各評価日付について、その評価日付より前のデータのみを使用
-- ----------------------------------------------------------------------------
strategy_simulation_base AS (
  -- 各評価日付と過去データの組み合わせ
  SELECT
    ed.evaluation_date,
    bd.target_date,
    bd.machine_number,
    bd.d1_diff,
    bd.d1_game,
    sc.strategy_name,
    sc.lt_type, sc.lt_threshold, sc.lt_threshold_upper, sc.lt_op,
    sc.lt_rank_type, sc.lt_rank_range,
    sc.st_period, sc.st_type, sc.st_threshold, sc.st_threshold_upper, sc.st_op
  FROM evaluation_dates ed
  CROSS JOIN base_data_with_special bd
  CROSS JOIN strategy_combinations sc
  WHERE
    -- 評価日付より前のデータのみを使用（未来の情報を使わない）
    bd.target_date < ed.evaluation_date
    AND 
    -- 長期条件の評価（prev_d28_*を使用）
    (
      sc.lt_type = 'none'
      OR
      (sc.lt_type = 'win_rate' AND bd.prev_d28_win_rate IS NOT NULL AND (
        (sc.lt_threshold_upper IS NULL AND (
          (sc.lt_op = '>=' AND bd.prev_d28_win_rate >= sc.lt_threshold) OR
          (sc.lt_op = '<' AND bd.prev_d28_win_rate < sc.lt_threshold)
        ))
        OR
        (sc.lt_threshold_upper IS NOT NULL AND (
          (sc.lt_op = '>=' AND bd.prev_d28_win_rate >= sc.lt_threshold AND bd.prev_d28_win_rate <= sc.lt_threshold_upper) OR
          (sc.lt_op = '>' AND bd.prev_d28_win_rate > sc.lt_threshold AND bd.prev_d28_win_rate <= sc.lt_threshold_upper)
        ))
      ))
      OR
      (sc.lt_type = 'payout_rate' AND (
        (sc.lt_threshold_upper IS NULL AND (
          (sc.lt_op = '>=' AND bd.prev_d28_payout_rate >= sc.lt_threshold) OR
          (sc.lt_op = '<' AND bd.prev_d28_payout_rate < sc.lt_threshold)
        ))
        OR
        (sc.lt_threshold_upper IS NOT NULL AND 
         bd.prev_d28_payout_rate >= sc.lt_threshold AND 
         bd.prev_d28_payout_rate < sc.lt_threshold_upper)
      ))
      OR
      (sc.lt_type = 'diff_rank' AND (
        (sc.lt_rank_type = 'best' AND (
          (sc.lt_rank_range = '1-5' AND bd.prev_d28_rank_best BETWEEN 1 AND 5) OR
          (sc.lt_rank_range = '6-10' AND bd.prev_d28_rank_best BETWEEN 6 AND 10)
        ))
        OR
        (sc.lt_rank_type = 'worst' AND (
          (sc.lt_rank_range = '1-5' AND bd.prev_d28_rank_worst BETWEEN 1 AND 5) OR
          (sc.lt_rank_range = '6-10' AND bd.prev_d28_rank_worst BETWEEN 6 AND 10)
        ))
      ))
    )
    AND
    -- 短期条件の評価
    (
      sc.st_type = 'none'
      OR
      (sc.st_type = 'win_rate' AND (
        CASE sc.st_period
          WHEN 3 THEN bd.prev_d3_win_rate
          WHEN 5 THEN bd.prev_d5_win_rate
          WHEN 7 THEN bd.prev_d7_win_rate
          ELSE NULL
        END IS NOT NULL AND (
          (sc.st_threshold_upper IS NULL AND (
            (sc.st_op = '>=' AND CASE sc.st_period WHEN 3 THEN bd.prev_d3_win_rate WHEN 5 THEN bd.prev_d5_win_rate WHEN 7 THEN bd.prev_d7_win_rate END >= sc.st_threshold) OR
            (sc.st_op = '>=' AND CASE sc.st_period WHEN 3 THEN bd.prev_d3_win_rate WHEN 5 THEN bd.prev_d5_win_rate WHEN 7 THEN bd.prev_d7_win_rate END = sc.st_threshold)
          ))
          OR
          (sc.st_threshold_upper IS NOT NULL AND (
            (sc.st_op = '>=' AND CASE sc.st_period WHEN 3 THEN bd.prev_d3_win_rate WHEN 5 THEN bd.prev_d5_win_rate WHEN 7 THEN bd.prev_d7_win_rate END >= sc.st_threshold AND CASE sc.st_period WHEN 3 THEN bd.prev_d3_win_rate WHEN 5 THEN bd.prev_d5_win_rate WHEN 7 THEN bd.prev_d7_win_rate END <= sc.st_threshold_upper) OR
            (sc.st_op = '>' AND CASE sc.st_period WHEN 3 THEN bd.prev_d3_win_rate WHEN 5 THEN bd.prev_d5_win_rate WHEN 7 THEN bd.prev_d7_win_rate END > sc.st_threshold AND CASE sc.st_period WHEN 3 THEN bd.prev_d3_win_rate WHEN 5 THEN bd.prev_d5_win_rate WHEN 7 THEN bd.prev_d7_win_rate END <= sc.st_threshold_upper)
          ))
        )
      ))
      OR
      (sc.st_type = 'digit_match_1' AND bd.machine_last_1digit = bd.date_last_1digit)
      OR
      (sc.st_type = 'digit_match_2' AND bd.machine_last_2digits = bd.date_last_2digits)
      OR
      (sc.st_type = 'digit_plus_1' AND bd.machine_last_1digit = MOD(bd.date_last_1digit + 1, 10))
      OR
      (sc.st_type = 'digit_minus_1' AND bd.machine_last_1digit = MOD(bd.date_last_1digit - 1 + 10, 10))
    )
),

strategy_simulation_results AS (
  SELECT
    ssb.evaluation_date,
    ssb.strategy_name,
    AVG(CASE WHEN ssb.d1_diff > 0 THEN 1.0 ELSE 0.0 END) AS win_rate,
    AVG((ssb.d1_game * 3 + ssb.d1_diff) / NULLIF(ssb.d1_game * 3, 0)) AS payout_rate,
    COUNT(*) AS ref_count,
    COUNT(DISTINCT ssb.target_date) AS days
  FROM strategy_simulation_base ssb
  GROUP BY ssb.evaluation_date, ssb.strategy_name
),

-- ----------------------------------------------------------------------------
-- 3-2. 各評価日付ごとの戦略有効性スコア計算
-- ----------------------------------------------------------------------------
-- パーセンタイル閾値
-- WIN_RATE_P25 = 0.357, WIN_RATE_P50 = 0.429, WIN_RATE_P75 = 0.50
-- PAYOUT_RATE_P25 = 1.0091, PAYOUT_RATE_P50 = 1.0247, PAYOUT_RATE_P75 = 1.0447
-- ----------------------------------------------------------------------------
strategy_effectiveness AS (
  SELECT
    ssr.evaluation_date,
    ssr.strategy_name,
    ssr.win_rate,
    ssr.payout_rate,
    ssr.ref_count,
    ssr.days,
    -- パーセンタイルスコア計算（勝率）
    CASE
      WHEN ssr.win_rate >= 0.50 THEN 1.0
      WHEN ssr.win_rate >= 0.429 THEN 0.5 + 0.5 * (ssr.win_rate - 0.429) / (0.50 - 0.429)
      WHEN ssr.win_rate >= 0.357 THEN 0.25 + 0.25 * (ssr.win_rate - 0.357) / (0.429 - 0.357)
      ELSE GREATEST(0, 0.25 * (ssr.win_rate / 0.357))
    END AS win_rate_percentile_score,
    -- パーセンタイルスコア計算（機械割）
    CASE
      WHEN ssr.payout_rate >= 1.0447 THEN 1.0
      WHEN ssr.payout_rate >= 1.0247 THEN 0.5 + 0.5 * (ssr.payout_rate - 1.0247) / (1.0447 - 1.0247)
      WHEN ssr.payout_rate >= 1.0091 THEN 0.25 + 0.25 * (ssr.payout_rate - 1.0091) / (1.0247 - 1.0091)
      ELSE GREATEST(0, 0.25 * (ssr.payout_rate / 1.0091))
    END AS payout_rate_percentile_score,
    -- 有効性スコア = (勝率スコア + 機械割スコア) / 2
    (CASE
      WHEN ssr.win_rate >= 0.50 THEN 1.0
      WHEN ssr.win_rate >= 0.429 THEN 0.5 + 0.5 * (ssr.win_rate - 0.429) / (0.50 - 0.429)
      WHEN ssr.win_rate >= 0.357 THEN 0.25 + 0.25 * (ssr.win_rate - 0.357) / (0.429 - 0.357)
      ELSE GREATEST(0, 0.25 * (ssr.win_rate / 0.357))
    END + CASE
      WHEN ssr.payout_rate >= 1.0447 THEN 1.0
      WHEN ssr.payout_rate >= 1.0247 THEN 0.5 + 0.5 * (ssr.payout_rate - 1.0247) / (1.0447 - 1.0247)
      WHEN ssr.payout_rate >= 1.0091 THEN 0.25 + 0.25 * (ssr.payout_rate - 1.0091) / (1.0247 - 1.0091)
      ELSE GREATEST(0, 0.25 * (ssr.payout_rate / 1.0091))
    END) / 2.0 AS effectiveness
  FROM strategy_simulation_results ssr
),

-- ############################################################################
-- Part 4: GASのロジックをSQLで再現
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 4-0. すべてのscore_methodを定義
-- ----------------------------------------------------------------------------
score_methods AS (
  SELECT method FROM UNNEST([
    'original',
    'simple',
    'rms_reliability',
    'rms_frequency',
    'strategy_filter',
    'rms_frequency_filter',
    'rms_frequency_anomaly',
    'rms_frequency_dual'
  ]) AS method
),

-- ----------------------------------------------------------------------------
-- 4-1a. 各評価日付について、推奨台のスコアを計算（フィルタなし版）
-- ----------------------------------------------------------------------------
evaluation_machine_scores_base AS (
  SELECT
    ecm.evaluation_date,
    ecm.machine_number,
    COUNT(DISTINCT ecm.strategy_name) AS match_count,
    SUM(COALESCE(se.ref_count, 1) * COALESCE(se.effectiveness, 1.0)) AS total_weight,
    SUM(COALESCE(se.ref_count, 1) * COALESCE(se.effectiveness, 1.0) * COALESCE(se.payout_rate, 0)) AS weighted_payout_rate,
    SUM(COALESCE(se.ref_count, 1) * COALESCE(se.effectiveness, 1.0) * COALESCE(se.win_rate, 0)) AS weighted_win_rate,
    SUM(COALESCE(se.days, 0)) AS total_days,
    SUM(COALESCE(se.ref_count, 0)) AS total_ref_count
  FROM evaluation_compound_machines ecm
  LEFT JOIN strategy_effectiveness se 
    ON ecm.evaluation_date = se.evaluation_date 
    AND ecm.strategy_name = se.strategy_name
  GROUP BY ecm.evaluation_date, ecm.machine_number
),

-- ----------------------------------------------------------------------------
-- 4-1b. 各評価日付について、推奨台のスコアを計算（フィルタあり版）
-- strategy_filter, rms_frequency_filter用: 有効性スコア0.5以上の戦略のみ使用
-- ----------------------------------------------------------------------------
evaluation_machine_scores_filtered AS (
  SELECT
    ecm.evaluation_date,
    ecm.machine_number,
    COUNT(DISTINCT ecm.strategy_name) AS match_count,
    SUM(COALESCE(se.ref_count, 1) * COALESCE(se.effectiveness, 1.0)) AS total_weight,
    SUM(COALESCE(se.ref_count, 1) * COALESCE(se.effectiveness, 1.0) * COALESCE(se.payout_rate, 0)) AS weighted_payout_rate,
    SUM(COALESCE(se.ref_count, 1) * COALESCE(se.effectiveness, 1.0) * COALESCE(se.win_rate, 0)) AS weighted_win_rate,
    SUM(COALESCE(se.days, 0)) AS total_days,
    SUM(COALESCE(se.ref_count, 0)) AS total_ref_count
  FROM evaluation_compound_machines ecm
  LEFT JOIN strategy_effectiveness se 
    ON ecm.evaluation_date = se.evaluation_date 
    AND ecm.strategy_name = se.strategy_name
  WHERE COALESCE(se.effectiveness, 1.0) >= 0.5
  GROUP BY ecm.evaluation_date, ecm.machine_number
),

-- ----------------------------------------------------------------------------
-- 4-1c. score_methodに応じて適切な版を選択
-- ----------------------------------------------------------------------------
evaluation_machine_scores AS (
  -- フィルタなし版を使うscore_methods
  SELECT
    sm.method AS score_method,
    emsb.evaluation_date,
    emsb.machine_number,
    emsb.match_count,
    emsb.total_weight,
    emsb.weighted_payout_rate,
    emsb.weighted_win_rate,
    emsb.total_days,
    emsb.total_ref_count
  FROM score_methods sm
  CROSS JOIN evaluation_machine_scores_base emsb
  WHERE sm.method NOT IN ('strategy_filter', 'rms_frequency_filter')
  UNION ALL
  -- フィルタあり版を使うscore_methods
  SELECT
    sm.method AS score_method,
    emsf.evaluation_date,
    emsf.machine_number,
    emsf.match_count,
    emsf.total_weight,
    emsf.weighted_payout_rate,
    emsf.weighted_win_rate,
    emsf.total_days,
    emsf.total_ref_count
  FROM score_methods sm
  CROSS JOIN evaluation_machine_scores_filtered emsf
  WHERE sm.method IN ('strategy_filter', 'rms_frequency_filter')
),

-- ----------------------------------------------------------------------------
-- 4-2. 各評価日付・各台番のスコア計算（GASのロジックをSQLで再現）
-- ----------------------------------------------------------------------------
evaluation_scores AS (
  SELECT
    ems.score_method,
    ems.evaluation_date,
    ems.machine_number,
    ems.match_count,
    -- 重み付け平均
    CASE 
      WHEN ems.total_weight > 0 THEN ems.weighted_payout_rate / ems.total_weight
      ELSE 0
    END AS weighted_avg_payout_rate,
    CASE 
      WHEN ems.total_weight > 0 THEN ems.weighted_win_rate / ems.total_weight
      ELSE 0
    END AS weighted_avg_win_rate,
    -- パーセンタイルスコア計算（勝率）
    CASE
      WHEN ems.total_weight > 0 AND ems.weighted_win_rate / ems.total_weight >= 0.50 THEN 1.0
      WHEN ems.total_weight > 0 AND ems.weighted_win_rate / ems.total_weight >= 0.429 
        THEN 0.5 + 0.5 * ((ems.weighted_win_rate / ems.total_weight) - 0.429) / (0.50 - 0.429)
      WHEN ems.total_weight > 0 AND ems.weighted_win_rate / ems.total_weight >= 0.357 
        THEN 0.25 + 0.25 * ((ems.weighted_win_rate / ems.total_weight) - 0.357) / (0.429 - 0.357)
      ELSE GREATEST(0, 0.25 * CASE WHEN ems.total_weight > 0 THEN (ems.weighted_win_rate / ems.total_weight) / 0.357 ELSE 0 END)
    END AS win_rate_percentile_score,
    -- パーセンタイルスコア計算（機械割）
    CASE
      WHEN ems.total_weight > 0 AND ems.weighted_payout_rate / ems.total_weight >= 1.0447 THEN 1.0
      WHEN ems.total_weight > 0 AND ems.weighted_payout_rate / ems.total_weight >= 1.0247 
        THEN 0.5 + 0.5 * ((ems.weighted_payout_rate / ems.total_weight) - 1.0247) / (1.0447 - 1.0247)
      WHEN ems.total_weight > 0 AND ems.weighted_payout_rate / ems.total_weight >= 1.0091 
        THEN 0.25 + 0.25 * ((ems.weighted_payout_rate / ems.total_weight) - 1.0091) / (1.0247 - 1.0091)
      ELSE GREATEST(0, 0.25 * CASE WHEN ems.total_weight > 0 THEN (ems.weighted_payout_rate / ems.total_weight) / 1.0091 ELSE 0 END)
    END AS payout_rate_percentile_score,
    ems.total_days,
    ems.total_ref_count
  FROM evaluation_machine_scores ems
),

-- ----------------------------------------------------------------------------
-- 4-3. 各評価日付での最大値計算（正規化用）
-- ----------------------------------------------------------------------------
evaluation_max_values AS (
  SELECT
    es.score_method,
    es.evaluation_date,
    MAX(es.total_days + es.total_ref_count) AS max_days_ref_count,
    MAX(es.match_count) AS max_match_count
  FROM evaluation_scores es
  GROUP BY es.score_method, es.evaluation_date
),

-- ----------------------------------------------------------------------------
-- 4-4. 総合スコア計算
-- ----------------------------------------------------------------------------
evaluation_total_scores AS (
  SELECT
    es.score_method,
    es.evaluation_date,
    es.machine_number,
    es.match_count,
    es.weighted_avg_payout_rate,
    es.weighted_avg_win_rate,
    es.win_rate_percentile_score,
    es.payout_rate_percentile_score,
    es.total_days,
    es.total_ref_count,
    -- RMS（パーセンタイルスコアベース）
    SQRT((es.win_rate_percentile_score * es.win_rate_percentile_score + 
          es.payout_rate_percentile_score * es.payout_rate_percentile_score) / 2) AS rms,
    -- 信頼性スコア
    CASE 
      WHEN emv.max_days_ref_count > 0 
        THEN LEAST((es.total_days + es.total_ref_count) / emv.max_days_ref_count, 1.0)
      ELSE 1.0
    END AS reliability_score,
    -- 出現頻度ボーナス
    CASE 
      WHEN emv.max_match_count > 0 
        THEN LEAST(SQRT(es.match_count) / SQRT(emv.max_match_count), 1.0)
      ELSE 1.0
    END AS frequency_bonus,
    -- 異常値ボーナス
    CASE
      WHEN es.weighted_avg_payout_rate > 1.0447 * 1.05 AND es.weighted_avg_win_rate > 0.50 * 1.1 THEN 1.1 * 1.1
      WHEN es.weighted_avg_payout_rate > 1.0447 * 1.05 THEN 1.1
      WHEN es.weighted_avg_win_rate > 0.50 * 1.1 THEN 1.1
      ELSE 1.0
    END AS anomaly_bonus,
    -- 複合ボーナス
    CASE
      WHEN es.weighted_avg_payout_rate >= 1.0247 AND es.weighted_avg_win_rate >= 0.429 THEN 1.1
      ELSE 1.0
    END AS dual_high_bonus
  FROM evaluation_scores es
  INNER JOIN evaluation_max_values emv 
    ON es.score_method = emv.score_method
    AND es.evaluation_date = emv.evaluation_date
),

-- ----------------------------------------------------------------------------
-- 4-5. 総合スコアの最終計算（score_methodに応じて切り替え）
-- ----------------------------------------------------------------------------
evaluation_final_scores AS (
  SELECT
    ets.score_method,
    ets.evaluation_date,
    ets.machine_number,
    ets.match_count,
    ets.weighted_avg_payout_rate,
    ets.weighted_avg_win_rate,
    ets.rms,
    ets.reliability_score,
    ets.frequency_bonus,
    ets.anomaly_bonus,
    ets.dual_high_bonus,
    -- 総合スコア（score_methodに応じて切り替え）
    CASE ets.score_method
      -- 改善案1: RMSのみ（シンプル化）
      WHEN 'simple' THEN ets.rms
      -- 改善案2: RMS × 信頼性（絶対閾値ベース）
      -- 信頼性スコアを絶対閾値で計算: days >= 30 AND ref_count >= 50 で 1.0
      WHEN 'rms_reliability' THEN 
        ets.rms * CASE 
          WHEN (ets.total_days >= 30 AND ets.total_ref_count >= 50) THEN 1.0
          WHEN (ets.total_days >= 20 AND ets.total_ref_count >= 30) THEN 0.8
          WHEN (ets.total_days >= 10 AND ets.total_ref_count >= 20) THEN 0.6
          ELSE 0.4
        END
      -- 改善案3: RMS × 頻度ボーナス
      WHEN 'rms_frequency' THEN ets.rms * ets.frequency_bonus
      -- ハイブリッド案1: RMS × 頻度 + 戦略フィルタ（戦略フィルタはevaluation_machine_scoresで適用済み）
      WHEN 'rms_frequency_filter' THEN ets.rms * ets.frequency_bonus
      -- ハイブリッド案2: RMS × 頻度 × 異常値ボーナス
      WHEN 'rms_frequency_anomaly' THEN ets.rms * ets.frequency_bonus * ets.anomaly_bonus
      -- ハイブリッド案3: RMS × 頻度 × 複合ボーナス
      WHEN 'rms_frequency_dual' THEN ets.rms * ets.frequency_bonus * ets.dual_high_bonus
      -- 改善案4: スコア閾値選別（TOP1の80%以上）は後でフィルタリング
      -- 元の計算方法
      ELSE ets.rms * ets.reliability_score * ets.frequency_bonus * ets.anomaly_bonus * ets.dual_high_bonus
    END AS total_score
  FROM evaluation_total_scores ets
),

-- ----------------------------------------------------------------------------
-- 4-6. 各評価日付でのランキング
-- ----------------------------------------------------------------------------
evaluation_rankings AS (
  SELECT
    efs.score_method,
    efs.evaluation_date,
    efs.machine_number,
    efs.total_score,
    ROW_NUMBER() OVER (PARTITION BY efs.score_method, efs.evaluation_date ORDER BY efs.total_score DESC) AS rank
  FROM evaluation_final_scores efs
),

-- ----------------------------------------------------------------------------
-- 4-6b. 各評価日のスコア統計（外れ値検出用・改善案4用）
-- ----------------------------------------------------------------------------
evaluation_score_stats AS (
  SELECT
    er.score_method,
    er.evaluation_date,
    AVG(er.total_score) AS avg_score,
    STDDEV(er.total_score) AS stddev_score,
    -- パーセンタイル（Q1, Q2, Q3）
    APPROX_QUANTILES(er.total_score, 4)[OFFSET(1)] AS q1_score,
    APPROX_QUANTILES(er.total_score, 4)[OFFSET(2)] AS median_score,
    APPROX_QUANTILES(er.total_score, 4)[OFFSET(3)] AS q3_score,
    MAX(er.total_score) AS max_score,
    MIN(er.total_score) AS min_score,
    -- 改善案4用: TOP1のスコアの各%以上
    MAX(CASE WHEN er.rank = 1 THEN er.total_score END) AS top1_score,
    MAX(CASE WHEN er.rank = 1 THEN er.total_score END) * 0.80 AS threshold_80pct,
    MAX(CASE WHEN er.rank = 1 THEN er.total_score END) * 0.85 AS threshold_85pct,
    MAX(CASE WHEN er.rank = 1 THEN er.total_score END) * 0.90 AS threshold_90pct,
    MAX(CASE WHEN er.rank = 1 THEN er.total_score END) * 0.95 AS threshold_95pct,
    MAX(CASE WHEN er.rank = 1 THEN er.total_score END) * 0.96 AS threshold_96pct,
    MAX(CASE WHEN er.rank = 1 THEN er.total_score END) * 0.97 AS threshold_97pct,
    MAX(CASE WHEN er.rank = 1 THEN er.total_score END) * 0.98 AS threshold_98pct,
    MAX(CASE WHEN er.rank = 1 THEN er.total_score END) * 0.99 AS threshold_99pct
  FROM evaluation_rankings er
  GROUP BY er.score_method, er.evaluation_date
),

-- ----------------------------------------------------------------------------
-- 4-6c. 外れ値閾値の計算
-- ----------------------------------------------------------------------------
evaluation_outlier_threshold AS (
  SELECT
    ess.score_method,
    ess.evaluation_date,
    ess.avg_score,
    ess.stddev_score,
    ess.q1_score,
    ess.q3_score,
    ess.q3_score - ess.q1_score AS iqr,
    -- 外れ値閾値: Q3 + 1.0*IQR または 平均 + 1.5*標準偏差 の小さい方
    -- （より多くの「飛び抜けて高い」台を拾うため）
    LEAST(
      ess.q3_score + 1.0 * (ess.q3_score - ess.q1_score),
      ess.avg_score + 1.5 * COALESCE(ess.stddev_score, 0)
    ) AS outlier_threshold
  FROM evaluation_score_stats ess
),

-- ############################################################################
-- Part 4: TOP1/TOP3/TOP5/外れ値の特定と実際のパフォーマンス集計
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 4-1. TOP1/TOP3/TOP5/外れ値の特定
-- ----------------------------------------------------------------------------
evaluation_top_n AS (
  SELECT
    er.score_method,
    er.evaluation_date,
    er.machine_number,
    er.total_score,
    er.rank,
    eot.outlier_threshold,
    CASE WHEN er.rank <= 1 THEN 1 ELSE 0 END AS is_top1,
    CASE WHEN er.rank <= 2 THEN 1 ELSE 0 END AS is_top2,
    CASE WHEN er.rank <= 3 THEN 1 ELSE 0 END AS is_top3,
    CASE WHEN er.rank <= 4 THEN 1 ELSE 0 END AS is_top4,
    CASE WHEN er.rank <= 5 THEN 1 ELSE 0 END AS is_top5,
    -- 外れ値（飛び抜けて高いスコア）かどうか
    CASE WHEN er.total_score >= eot.outlier_threshold THEN 1 ELSE 0 END AS is_outlier,
    -- 各しきい値判定（TOP1のスコアの各%以上）
    CASE WHEN er.total_score >= ess.threshold_80pct THEN 1 ELSE 0 END AS is_threshold_80pct,
    CASE WHEN er.total_score >= ess.threshold_85pct THEN 1 ELSE 0 END AS is_threshold_85pct,
    CASE WHEN er.total_score >= ess.threshold_90pct THEN 1 ELSE 0 END AS is_threshold_90pct,
    CASE WHEN er.total_score >= ess.threshold_95pct THEN 1 ELSE 0 END AS is_threshold_95pct,
    CASE WHEN er.total_score >= ess.threshold_96pct THEN 1 ELSE 0 END AS is_threshold_96pct,
    CASE WHEN er.total_score >= ess.threshold_97pct THEN 1 ELSE 0 END AS is_threshold_97pct,
    CASE WHEN er.total_score >= ess.threshold_98pct THEN 1 ELSE 0 END AS is_threshold_98pct,
    CASE WHEN er.total_score >= ess.threshold_99pct THEN 1 ELSE 0 END AS is_threshold_99pct
  FROM evaluation_rankings er
  INNER JOIN evaluation_outlier_threshold eot 
    ON er.score_method = eot.score_method
    AND er.evaluation_date = eot.evaluation_date
  INNER JOIN evaluation_score_stats ess 
    ON er.score_method = ess.score_method
    AND er.evaluation_date = ess.evaluation_date
  WHERE er.rank <= 10  -- 外れ値用に少し多めに取得
),

-- ----------------------------------------------------------------------------
-- 4-2. 実際のパフォーマンス（次の日のデータ）
-- ----------------------------------------------------------------------------
evaluation_actual_performance AS (
  SELECT
    etn.score_method,
    etn.evaluation_date,
    etn.machine_number,
    etn.total_score,
    etn.rank,
    etn.outlier_threshold,
    etn.is_top1,
    etn.is_top2,
    etn.is_top3,
    etn.is_top4,
    etn.is_top5,
    etn.is_outlier,
    etn.is_threshold_80pct,
    etn.is_threshold_85pct,
    etn.is_threshold_90pct,
    etn.is_threshold_95pct,
    etn.is_threshold_96pct,
    etn.is_threshold_97pct,
    etn.is_threshold_98pct,
    etn.is_threshold_99pct,
    bd.d1_diff AS actual_diff,
    bd.d1_game AS actual_game,
    CASE WHEN bd.d1_diff > 0 THEN 1 ELSE 0 END AS is_win,
    (bd.d1_game * 3 + bd.d1_diff) / NULLIF(bd.d1_game * 3, 0) AS actual_payout_rate
  FROM evaluation_top_n etn
  INNER JOIN base_data bd 
    ON etn.evaluation_date = bd.target_date 
    AND etn.machine_number = bd.machine_number
),

-- ############################################################################
-- Part 4b: 集計タイプ定義
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 4-3a. 集計タイプの定義（UNION ALLを削減）
-- ----------------------------------------------------------------------------
result_types AS (
  SELECT * FROM UNNEST([
    STRUCT('TOP1' AS type_name, 1 AS sort_order),
    STRUCT('TOP2', 2),
    STRUCT('TOP3', 3),
    STRUCT('TOP4', 4),
    STRUCT('TOP5', 5),
    STRUCT('OUTLIER', 6),
    STRUCT('THRESHOLD_80PCT', 7),
    STRUCT('THRESHOLD_85PCT', 8),
    STRUCT('THRESHOLD_90PCT', 9),
    STRUCT('THRESHOLD_95PCT', 10),
    STRUCT('THRESHOLD_96PCT', 11),
    STRUCT('THRESHOLD_97PCT', 12),
    STRUCT('THRESHOLD_98PCT', 13),
    STRUCT('THRESHOLD_99PCT', 14)
  ])
),

-- ----------------------------------------------------------------------------
-- 4-3b. 集計（CROSS JOINで一括処理）
-- ----------------------------------------------------------------------------
evaluation_summary AS (
  SELECT
    eap.score_method,
    rt.type_name AS top_n,
    rt.sort_order,
    COUNT(DISTINCT eap.evaluation_date) AS evaluation_days,
    COUNT(*) AS total_machines,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT eap.evaluation_date), 2) AS avg_machines_per_day,
    SUM(eap.is_win) AS win_days,
    ROUND(AVG(eap.is_win) * 100, 2) AS win_rate,
    SUM(eap.actual_diff) AS total_diff,
    ROUND(AVG(eap.actual_diff), 0) AS avg_diff,
    ROUND(AVG(eap.actual_payout_rate) * 100, 2) AS payout_rate,
    MAX(eap.actual_diff) AS max_diff,
    MIN(eap.actual_diff) AS min_diff
  FROM evaluation_actual_performance eap
  CROSS JOIN result_types rt
  WHERE 
    (rt.type_name = 'TOP1' AND eap.is_top1 = 1) OR
    (rt.type_name = 'TOP2' AND eap.is_top2 = 1) OR
    (rt.type_name = 'TOP3' AND eap.is_top3 = 1) OR
    (rt.type_name = 'TOP4' AND eap.is_top4 = 1) OR
    (rt.type_name = 'TOP5' AND eap.is_top5 = 1) OR
    (rt.type_name = 'OUTLIER' AND eap.is_outlier = 1) OR
    (rt.type_name = 'THRESHOLD_80PCT' AND eap.is_threshold_80pct = 1) OR
    (rt.type_name = 'THRESHOLD_85PCT' AND eap.is_threshold_85pct = 1) OR
    (rt.type_name = 'THRESHOLD_90PCT' AND eap.is_threshold_90pct = 1) OR
    (rt.type_name = 'THRESHOLD_95PCT' AND eap.is_threshold_95pct = 1) OR
    (rt.type_name = 'THRESHOLD_96PCT' AND eap.is_threshold_96pct = 1) OR
    (rt.type_name = 'THRESHOLD_97PCT' AND eap.is_threshold_97pct = 1) OR
    (rt.type_name = 'THRESHOLD_98PCT' AND eap.is_threshold_98pct = 1) OR
    (rt.type_name = 'THRESHOLD_99PCT' AND eap.is_threshold_99pct = 1)
  GROUP BY eap.score_method, rt.type_name, rt.sort_order
)

-- ############################################################################
-- Part 5: 最終出力
-- ############################################################################
SELECT
  score_method,
  top_n AS result_key,
  CAST(NULL AS STRING) AS result_detail,
  evaluation_days,
  total_machines,
  avg_machines_per_day,
  win_days,
  win_rate,
  total_diff,
  avg_diff,
  payout_rate,
  max_diff,
  min_diff
FROM evaluation_summary
ORDER BY score_method, sort_order

