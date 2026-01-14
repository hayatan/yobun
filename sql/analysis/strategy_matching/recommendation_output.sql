-- ============================================================================
-- 狙い台一覧出力クエリ（複数店舗・複数機種対応版）
-- ============================================================================
-- 
-- 【概要】
--   recommendation_evaluation.sql と同じロジックを使用して、
--   最終的な「狙い台一覧」を出力する。
--   複数の店舗・機種の推奨台を1回のクエリで取得可能。
--   機種ごとに評価結果に基づいた最適なスコア計算メソッドを指定可能。
--   スコア計算と優先度ランク付けまでSQLで完結。
--   BigQuery Connector から直接使用可能。
--
-- 【出力項目】
--   - hole_name: 店舗名
--   - machine_name: 機種名
--   - score_method: スコア計算メソッド
--   - target_date: 推奨日付
--   - machine_number: 台番
--   - priority_rank: 優先度ランク（5=最高、1=最低、0=対象外）
--   - total_score: 総合スコア
--   - top1_ratio: TOP1スコアとの比率（0〜1）
--   - rank: 店舗・機種・メソッド内でのランキング
--   - match_count: 該当戦略数
--   - weighted_payout_rate: 重み付け機械割（0〜1、例: 1.085 = 108.5%）
--   - weighted_win_rate: 重み付け勝率（0〜1、例: 0.583 = 58.3%）
--   - rms: RMSスコア
--   - frequency_bonus: 出現頻度ボーナス
--   - reliability_score: 信頼性スコア
--   - anomaly_bonus: 異常値ボーナス
--   - dual_high_bonus: 複合ボーナス
--
-- 【優先度ランクの定義】
--   TOP1スコア（各店舗・機種・メソッド内での最高スコア）との比率に基づく
--   5: TOP1スコアの99%以上（最優先）
--   4: TOP1スコアの97%以上
--   3: TOP1スコアの95%以上
--   2: TOP1スコアの90%以上
--   1: TOP1スコアの80%以上（参考程度）
--   0: それ以外
--   ※ 実際の期待勝率・機械割は店舗・機種・評価期間によって異なる
--   ※ 評価結果（results/YYYY-MM-DD/summary.md）を参照のこと
--
-- 【スコア計算メソッド】
--   - original: 元の計算方法（RMS × 信頼性 × 頻度 × 異常値 × 複合）
--   - simple: RMSのみ
--   - rms_reliability: RMS × 信頼性（絶対閾値ベース）
--   - rms_frequency: RMS × 頻度ボーナス
--   - rms_frequency_filter: RMS × 頻度（有効性スコア0.5以上の戦略のみ）
--   - rms_frequency_anomaly: RMS × 頻度 × 異常値ボーナス
--   - rms_frequency_dual: RMS × 頻度 × 複合ボーナス
--
-- 【パラメータ定義】
-- ============================================================================
-- ★★★ BigQuery Connector で使用する場合 ★★★
-- BigQuery Connector は DECLARE 文をサポートしていないため、
-- 以下の params CTE 内の値を直接変更してください。
-- 評価結果に基づき、機種ごとに最適なメソッドを指定できます。
-- ============================================================================

-- 【パーセンタイル閾値】
-- ============================================================================
-- 勝率（過去28日間）: P25=0.357, P50=0.429, P75=0.50
-- 機械割（過去28日間）: P25=1.0091, P50=1.0247, P75=1.0447

WITH

-- ############################################################################
-- Part 0: パラメータ定義（BigQuery Connector 用）
-- ############################################################################
-- ★★★ 対象店舗・機種を変更する場合は、ここを編集してください ★★★
-- 評価結果に基づき、機種ごとに最適なメソッドを指定
-- 同一機種で複数メソッドを指定することも可能
-- 
-- 【特日タイプ（special_day_type）】
--   'island' = アイランド秋葉原店（6,16,26日、月末）
--   'espas'  = エスパス秋葉原駅前店（6,16,26日、14日、月末）
--   'none'   = 特日なし（全日を通常日として扱う）
--
-- 【スコア計算メソッド（score_method）】
--   'original'             = 元の計算方法（RMS × 信頼性 × 頻度 × 異常値 × 複合）
--   'simple'               = RMSのみ
--   'rms_reliability'      = RMS × 信頼性（絶対閾値ベース）
--   'rms_frequency'        = RMS × 頻度ボーナス
--   'rms_frequency_filter' = RMS × 頻度（有効性スコア0.5以上の戦略のみ）
--   'rms_frequency_anomaly'= RMS × 頻度 × 異常値ボーナス
--   'rms_frequency_dual'   = RMS × 頻度 × 複合ボーナス
-- ############################################################################
params AS (
  SELECT * FROM UNNEST([
    -- ===== アイランド秋葉原店 =====
    -- L+ToLOVEるダークネス: 最優秀（勝率59%, 機械割108%）
    STRUCT(CAST(NULL AS DATE) AS target_date, 'アイランド秋葉原店' AS target_hole, 'L+ToLOVEるダークネス' AS target_machine, 'island' AS special_day_type, 'original' AS score_method),
    -- Lバンドリ！: 短期改善傾向
    STRUCT(CAST(NULL AS DATE), 'アイランド秋葉原店', 'Lバンドリ！', 'island', 'original'),
    -- マギアレコード: 中程度
    STRUCT(CAST(NULL AS DATE), 'アイランド秋葉原店', 'スマスロ+マギアレコード+魔法少女まどか☆マギカ外伝', 'island', 'original'),
    -- L戦国乙女４: 短期改善傾向
    STRUCT(CAST(NULL AS DATE), 'アイランド秋葉原店', 'L戦国乙女４　戦乱に閃く炯眼の軍師', 'island', 'original'),
    
    -- ===== エスパス秋葉原駅前店 =====
    -- Lソードアート・オンライン: 優秀（勝率62%, 機械割106%）
    STRUCT(CAST(NULL AS DATE), 'エスパス秋葉原駅前店', 'Lソードアート・オンライン', 'espas', 'rms_frequency'),
    -- L戦国乙女４: 短期改善傾向
    STRUCT(CAST(NULL AS DATE), 'エスパス秋葉原駅前店', 'L戦国乙女４　戦乱に閃く炯眼の軍師', 'espas', 'rms_frequency'),
    -- マギアレコード: 優秀（勝率64%, 機械割105%）
    STRUCT(CAST(NULL AS DATE), 'エスパス秋葉原駅前店', 'スマスロ+マギアレコード+魔法少女まどか☆マギカ外伝', 'espas', 'rms_frequency')
  ])
),

-- ############################################################################
-- Part 1: 基本データの取得
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 1-1. 対象日付の決定（店舗・機種ごとに最新日を取得）
-- ----------------------------------------------------------------------------
target_date_calc AS (
  SELECT
    p.target_hole,
    p.target_machine,
    p.special_day_type,
    p.score_method,
    CASE
      WHEN p.target_date IS NOT NULL THEN p.target_date
      ELSE DATE_ADD(max_date.latest_date, INTERVAL 1 DAY)
    END AS calc_target_date
  FROM params p
  LEFT JOIN (
    SELECT hole, machine, MAX(target_date) AS latest_date
    FROM `yobun-450512.datamart.machine_stats`
    GROUP BY hole, machine
  ) max_date ON p.target_hole = max_date.hole AND p.target_machine = max_date.machine
),

-- ----------------------------------------------------------------------------
-- 1-2. 基本データの取得（店舗・機種・メソッドごと）
-- ----------------------------------------------------------------------------
base_data AS (
  SELECT
    p.target_hole,
    p.target_machine,
    p.special_day_type,
    p.score_method,
    ms.target_date,
    ms.machine_number,
    -- 当日データ
    ms.d1_diff,
    ms.d1_game,
    -- 過去データ（前日時点）
    ms.prev_d3_win_rate,
    ms.prev_d5_win_rate,
    ms.prev_d7_win_rate,
    ms.prev_d28_win_rate,
    ms.prev_d28_payout_rate,
    ms.prev_d28_diff,
    -- 日付・台番の末尾
    MOD(EXTRACT(DAY FROM ms.target_date), 10) AS date_last_1digit,
    EXTRACT(DAY FROM ms.target_date) AS date_last_2digits,
    MOD(CAST(ms.machine_number AS INT64), 10) AS machine_last_1digit,
    MOD(CAST(ms.machine_number AS INT64), 100) AS machine_last_2digits,
    -- 差枚ランキング（当日基準、店舗・機種・メソッドごと）
    ROW_NUMBER() OVER (PARTITION BY p.target_hole, p.target_machine, p.score_method, ms.target_date ORDER BY ms.prev_d28_diff DESC) AS prev_d28_rank_best,
    ROW_NUMBER() OVER (PARTITION BY p.target_hole, p.target_machine, p.score_method, ms.target_date ORDER BY ms.prev_d28_diff ASC) AS prev_d28_rank_worst
  FROM `yobun-450512.datamart.machine_stats` ms
  INNER JOIN params p ON ms.hole = p.target_hole AND ms.machine = p.target_machine
),

-- ----------------------------------------------------------------------------
-- 1-3. 特日定義（店舗ごとに異なる）
-- ----------------------------------------------------------------------------
special_day_logic AS (
  SELECT 
    tdc.target_hole,
    tdc.target_machine,
    tdc.special_day_type,
    tdc.score_method,
    tdc.calc_target_date AS target_date,
    CASE tdc.special_day_type
      -- アイランド秋葉原店: 6,16,26日、月末
      WHEN 'island' THEN
        CASE 
          WHEN EXTRACT(DAY FROM tdc.calc_target_date) IN (6, 16, 26) THEN TRUE
          WHEN tdc.calc_target_date = LAST_DAY(tdc.calc_target_date) THEN TRUE
          ELSE FALSE
        END
      -- エスパス秋葉原駅前店: 6のつく日、14日、月末
      WHEN 'espas' THEN
        CASE 
          WHEN EXTRACT(DAY FROM tdc.calc_target_date) IN (6, 16, 26) THEN TRUE
          WHEN EXTRACT(DAY FROM tdc.calc_target_date) = 14 THEN TRUE
          WHEN tdc.calc_target_date = LAST_DAY(tdc.calc_target_date) THEN TRUE
          ELSE FALSE
        END
      -- 特日なし: 全日を通常日として扱う
      WHEN 'none' THEN FALSE
      -- デフォルト: 特日なし
      ELSE FALSE
    END AS is_special_day
  FROM target_date_calc tdc
),

-- ----------------------------------------------------------------------------
-- 1-4. 推奨対象日の情報
-- ----------------------------------------------------------------------------
next_day_info AS (
  SELECT
    sdl.target_hole,
    sdl.target_machine,
    sdl.special_day_type,
    sdl.score_method,
    sdl.target_date AS next_date,
    MOD(EXTRACT(DAY FROM sdl.target_date), 10) AS next_date_last_1digit,
    EXTRACT(DAY FROM sdl.target_date) AS next_date_last_2digits,
    sdl.is_special_day AS next_is_special_day
  FROM special_day_logic sdl
),

-- ----------------------------------------------------------------------------
-- 1-5. 推奨対象日の前日を取得
-- ----------------------------------------------------------------------------
prev_day AS (
  SELECT 
    target_hole,
    target_machine,
    special_day_type,
    score_method,
    DATE_SUB(calc_target_date, INTERVAL 1 DAY) AS prev_date
  FROM target_date_calc
),

-- ----------------------------------------------------------------------------
-- 1-6. 最新データ（推奨対象日の前日データのみ）
-- ----------------------------------------------------------------------------
-- ★★★ 台番号の入れ替えを考慮 ★★★
-- 「推奨対象日の前日」に存在する台番号のみを対象にする
-- これにより、過去に別の機種だった台番号（現在は存在しない）を除外
current_data AS (
  SELECT
    bd.*
  FROM base_data bd
  INNER JOIN prev_day pd 
    ON bd.target_hole = pd.target_hole
    AND bd.target_machine = pd.target_machine
    AND bd.score_method = pd.score_method
    AND bd.target_date = pd.prev_date
),

-- ############################################################################
-- Part 2: 戦略条件の定義
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 2-1. 長期条件マスタ
-- ----------------------------------------------------------------------------
long_term_conditions AS (
  SELECT * FROM UNNEST([
    -- 条件なし
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
    -- 過去28日間勝率（パーセンタイルベース）
    STRUCT('過去28日間勝率50.0%以上' AS lt_name, 'win_rate' AS lt_type, 0.50 AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, '>=' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 1 AS lt_sort),
    STRUCT('過去28日間勝率42.9%以上50.0%未満' AS lt_name, 'win_rate' AS lt_type, 0.429 AS lt_threshold, 0.50 AS lt_threshold_upper, '>=' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 2 AS lt_sort),
    STRUCT('過去28日間勝率35.7%以上42.9%未満' AS lt_name, 'win_rate' AS lt_type, 0.357 AS lt_threshold, 0.429 AS lt_threshold_upper, '>=' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 3 AS lt_sort),
    STRUCT('過去28日間勝率35.7%未満' AS lt_name, 'win_rate' AS lt_type, 0.357 AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, '<' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 4 AS lt_sort),
    -- 過去28日間機械割（パーセンタイルベース）
    STRUCT('過去28日間機械割104.47%以上' AS lt_name, 'payout_rate' AS lt_type, 1.0447 AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, '>=' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 7 AS lt_sort),
    STRUCT('過去28日間機械割102.47%以上104.47%未満' AS lt_name, 'payout_rate' AS lt_type, 1.0247 AS lt_threshold, 1.0447 AS lt_threshold_upper, '>=' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 8 AS lt_sort),
    STRUCT('過去28日間機械割100.91%以上102.47%未満' AS lt_name, 'payout_rate' AS lt_type, 1.0091 AS lt_threshold, 1.0247 AS lt_threshold_upper, '>=' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 9 AS lt_sort),
    STRUCT('過去28日間機械割100.91%未満' AS lt_name, 'payout_rate' AS lt_type, 1.0091 AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, '<' AS lt_op, CAST(NULL AS STRING) AS lt_rank_type, CAST(NULL AS STRING) AS lt_rank_range, 10 AS lt_sort),
    -- 過去28日間差枚（ランキングベース）
    STRUCT('過去28日間差枚ベスト1~5' AS lt_name, 'diff_rank' AS lt_type, CAST(NULL AS FLOAT64) AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, CAST(NULL AS STRING) AS lt_op, 'best' AS lt_rank_type, '1-5' AS lt_rank_range, 11 AS lt_sort),
    STRUCT('過去28日間差枚ベスト6~10' AS lt_name, 'diff_rank' AS lt_type, CAST(NULL AS FLOAT64) AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, CAST(NULL AS STRING) AS lt_op, 'best' AS lt_rank_type, '6-10' AS lt_rank_range, 12 AS lt_sort),
    STRUCT('過去28日間差枚ワースト1~5' AS lt_name, 'diff_rank' AS lt_type, CAST(NULL AS FLOAT64) AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, CAST(NULL AS STRING) AS lt_op, 'worst' AS lt_rank_type, '1-5' AS lt_rank_range, 13 AS lt_sort),
    STRUCT('過去28日間差枚ワースト6~10' AS lt_name, 'diff_rank' AS lt_type, CAST(NULL AS FLOAT64) AS lt_threshold, CAST(NULL AS FLOAT64) AS lt_threshold_upper, CAST(NULL AS STRING) AS lt_op, 'worst' AS lt_rank_type, '6-10' AS lt_rank_range, 14 AS lt_sort)
  ])
),

-- ----------------------------------------------------------------------------
-- 2-2. 短期条件マスタ（勝率）
-- ----------------------------------------------------------------------------
short_term_win_rate_conditions AS (
  SELECT * FROM UNNEST([
    STRUCT('' AS st_name, 0 AS st_period, 'none' AS st_type, 0.0 AS st_threshold, '' AS st_op, CAST(NULL AS FLOAT64) AS st_threshold_upper, 0 AS st_sort),
    -- 過去3日間勝率（評価クエリと同じ）
    STRUCT('+過去3日間勝率100%', 3, 'win_rate', 1.0, '>=', 1.0, 1),
    STRUCT('+過去3日間勝率75%超100%未満', 3, 'win_rate', 0.75, '>', 1.0, 2),
    STRUCT('+過去3日間勝率50%超75%以下', 3, 'win_rate', 0.5, '>', 0.75, 3),
    STRUCT('+過去3日間勝率25%超50%以下', 3, 'win_rate', 0.25, '>', 0.5, 4),
    STRUCT('+過去3日間勝率0%超25%未満', 3, 'win_rate', 0.0, '>', 0.25, 5),
    STRUCT('+過去3日間勝率0%', 3, 'win_rate', 0.0, '>=', 0.0, 6),
    -- 過去5日間勝率
    STRUCT('+過去5日間勝率100%', 5, 'win_rate', 1.0, '>=', 1.0, 11),
    STRUCT('+過去5日間勝率75%超100%未満', 5, 'win_rate', 0.75, '>', 1.0, 12),
    STRUCT('+過去5日間勝率50%超75%以下', 5, 'win_rate', 0.5, '>', 0.75, 13),
    STRUCT('+過去5日間勝率25%超50%以下', 5, 'win_rate', 0.25, '>', 0.5, 14),
    STRUCT('+過去5日間勝率0%超25%未満', 5, 'win_rate', 0.0, '>', 0.25, 15),
    STRUCT('+過去5日間勝率0%', 5, 'win_rate', 0.0, '>=', 0.0, 16),
    -- 過去7日間勝率
    STRUCT('+過去7日間勝率100%', 7, 'win_rate', 1.0, '>=', 1.0, 21),
    STRUCT('+過去7日間勝率75%超100%未満', 7, 'win_rate', 0.75, '>', 1.0, 22),
    STRUCT('+過去7日間勝率50%超75%以下', 7, 'win_rate', 0.5, '>', 0.75, 23),
    STRUCT('+過去7日間勝率25%超50%以下', 7, 'win_rate', 0.25, '>', 0.5, 24),
    STRUCT('+過去7日間勝率0%超25%未満', 7, 'win_rate', 0.0, '>', 0.25, 25),
    STRUCT('+過去7日間勝率0%', 7, 'win_rate', 0.0, '>=', 0.0, 26)
  ])
),

-- ----------------------------------------------------------------------------
-- 2-3. 短期条件マスタ（末尾関連性）
-- ----------------------------------------------------------------------------
short_term_digit_conditions AS (
  SELECT * FROM UNNEST([
    STRUCT('' AS st_name, 0 AS st_period, 'none' AS st_type, 0.0 AS st_threshold, '' AS st_op, CAST(NULL AS FLOAT64) AS st_threshold_upper, 0 AS st_sort),
    STRUCT('+台番末尾1桁=日付末尾1桁', 0, 'digit_match_1', 0.0, '', CAST(NULL AS FLOAT64), 30),
    STRUCT('+台番末尾2桁=日付末尾2桁', 0, 'digit_match_2', 0.0, '', CAST(NULL AS FLOAT64), 31),
    STRUCT('+台番末尾1桁=日付末尾1桁+1', 0, 'digit_plus_1', 0.0, '', CAST(NULL AS FLOAT64), 32),
    STRUCT('+台番末尾1桁=日付末尾1桁-1', 0, 'digit_minus_1', 0.0, '', CAST(NULL AS FLOAT64), 33),
    -- 特日条件
    STRUCT('+特日', 0, 'special_day', 0.0, '', CAST(NULL AS FLOAT64), 40),
    STRUCT('+特日以外', 0, 'non_special_day', 0.0, '', CAST(NULL AS FLOAT64), 41)
  ])
),

-- ----------------------------------------------------------------------------
-- 2-4. 短期条件の統合
-- ----------------------------------------------------------------------------
short_term_conditions AS (
  SELECT * FROM short_term_win_rate_conditions
  UNION ALL
  SELECT * FROM short_term_digit_conditions
),

-- ----------------------------------------------------------------------------
-- 2-5. 戦略の組み合わせ
-- ----------------------------------------------------------------------------
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
  WHERE NOT (
    -- 長期条件と末尾条件・特日条件は組み合わせない（ノイズになるため）
    lt.lt_type != 'none' AND st.st_type IN ('digit_match_1', 'digit_match_2', 'digit_plus_1', 'digit_minus_1', 'special_day', 'non_special_day')
  )
),

-- ############################################################################
-- Part 3: 戦略シミュレーション（過去データ）
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 3-1. 現在の台番号リスト（台番号の入れ替えを考慮）
-- ----------------------------------------------------------------------------
-- 推奨対象日の前日時点で存在する台番号のみを対象にする
-- これにより、過去に別の機種だった台番号のデータを除外
current_machine_numbers AS (
  SELECT DISTINCT 
    target_hole,
    target_machine,
    special_day_type,
    score_method,
    machine_number
  FROM current_data
),

-- ----------------------------------------------------------------------------
-- 3-2. 過去データでの戦略シミュレーション（現在の台番号のみ）
-- ----------------------------------------------------------------------------
strategy_simulation AS (
  SELECT
    bd.target_hole,
    bd.target_machine,
    bd.special_day_type,
    bd.score_method,
    bd.target_date,
    bd.machine_number,
    sc.strategy_name,
    sc.lt_type,
    sc.st_type,
    -- 次の日のパフォーマンス（店舗・機種・メソッドごとにパーティション）
    LEAD(bd.d1_diff) OVER (PARTITION BY bd.target_hole, bd.target_machine, bd.score_method, bd.machine_number ORDER BY bd.target_date) AS next_diff,
    LEAD(bd.d1_game) OVER (PARTITION BY bd.target_hole, bd.target_machine, bd.score_method, bd.machine_number ORDER BY bd.target_date) AS next_game
  FROM base_data bd
  -- ★★★ 現在の台番号のみを対象（台番号入れ替えを考慮）★★★
  INNER JOIN current_machine_numbers cmn 
    ON bd.target_hole = cmn.target_hole
    AND bd.target_machine = cmn.target_machine
    AND bd.score_method = cmn.score_method
    AND bd.machine_number = cmn.machine_number
  CROSS JOIN strategy_combinations sc
  WHERE
    -- 長期条件の評価
    (sc.lt_type = 'none') OR
    (sc.lt_type = 'win_rate' AND sc.lt_op = '>=' AND sc.lt_threshold_upper IS NULL AND bd.prev_d28_win_rate >= sc.lt_threshold) OR
    (sc.lt_type = 'win_rate' AND sc.lt_op = '>=' AND sc.lt_threshold_upper IS NOT NULL AND bd.prev_d28_win_rate >= sc.lt_threshold AND bd.prev_d28_win_rate < sc.lt_threshold_upper) OR
    (sc.lt_type = 'win_rate' AND sc.lt_op = '<' AND bd.prev_d28_win_rate < sc.lt_threshold) OR
    (sc.lt_type = 'payout_rate' AND sc.lt_op = '>=' AND sc.lt_threshold_upper IS NULL AND bd.prev_d28_payout_rate >= sc.lt_threshold) OR
    (sc.lt_type = 'payout_rate' AND sc.lt_op = '>=' AND sc.lt_threshold_upper IS NOT NULL AND bd.prev_d28_payout_rate >= sc.lt_threshold AND bd.prev_d28_payout_rate < sc.lt_threshold_upper) OR
    (sc.lt_type = 'payout_rate' AND sc.lt_op = '<' AND bd.prev_d28_payout_rate < sc.lt_threshold) OR
    (sc.lt_type = 'diff_rank' AND sc.lt_rank_type = 'best' AND sc.lt_rank_range = '1-5' AND bd.prev_d28_rank_best <= 5) OR
    (sc.lt_type = 'diff_rank' AND sc.lt_rank_type = 'best' AND sc.lt_rank_range = '6-10' AND bd.prev_d28_rank_best BETWEEN 6 AND 10) OR
    (sc.lt_type = 'diff_rank' AND sc.lt_rank_type = 'worst' AND sc.lt_rank_range = '1-5' AND bd.prev_d28_rank_worst <= 5) OR
    (sc.lt_type = 'diff_rank' AND sc.lt_rank_type = 'worst' AND sc.lt_rank_range = '6-10' AND bd.prev_d28_rank_worst BETWEEN 6 AND 10)
  AND
    -- 短期条件の評価（評価クエリと同じロジック）
    (sc.st_type = 'none') OR
    -- 勝率100%（>= 1.0 AND <= 1.0）
    (sc.st_type = 'win_rate' AND sc.st_op = '>=' AND sc.st_threshold = 1.0 AND sc.st_threshold_upper = 1.0 AND (
      (sc.st_period = 3 AND bd.prev_d3_win_rate = 1.0) OR
      (sc.st_period = 5 AND bd.prev_d5_win_rate = 1.0) OR
      (sc.st_period = 7 AND bd.prev_d7_win_rate = 1.0)
    )) OR
    -- 勝率0%（>= 0.0 AND <= 0.0）
    (sc.st_type = 'win_rate' AND sc.st_op = '>=' AND sc.st_threshold = 0.0 AND sc.st_threshold_upper = 0.0 AND (
      (sc.st_period = 3 AND bd.prev_d3_win_rate = 0.0) OR
      (sc.st_period = 5 AND bd.prev_d5_win_rate = 0.0) OR
      (sc.st_period = 7 AND bd.prev_d7_win_rate = 0.0)
    )) OR
    -- 勝率範囲（> threshold AND < upper または <= upper）
    (sc.st_type = 'win_rate' AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND (
      (sc.st_period = 3 AND bd.prev_d3_win_rate > sc.st_threshold AND bd.prev_d3_win_rate < sc.st_threshold_upper) OR
      (sc.st_period = 5 AND bd.prev_d5_win_rate > sc.st_threshold AND bd.prev_d5_win_rate < sc.st_threshold_upper) OR
      (sc.st_period = 7 AND bd.prev_d7_win_rate > sc.st_threshold AND bd.prev_d7_win_rate < sc.st_threshold_upper) OR
      -- 50%超75%以下の場合は <= を使用
      (sc.st_threshold = 0.5 AND sc.st_period = 3 AND bd.prev_d3_win_rate > sc.st_threshold AND bd.prev_d3_win_rate <= sc.st_threshold_upper) OR
      (sc.st_threshold = 0.5 AND sc.st_period = 5 AND bd.prev_d5_win_rate > sc.st_threshold AND bd.prev_d5_win_rate <= sc.st_threshold_upper) OR
      (sc.st_threshold = 0.5 AND sc.st_period = 7 AND bd.prev_d7_win_rate > sc.st_threshold AND bd.prev_d7_win_rate <= sc.st_threshold_upper)
    )) OR
    (sc.st_type = 'digit_match_1' AND bd.machine_last_1digit = bd.date_last_1digit) OR
    (sc.st_type = 'digit_match_2' AND bd.machine_last_2digits = bd.date_last_2digits) OR
    (sc.st_type = 'digit_plus_1' AND bd.machine_last_1digit = MOD(bd.date_last_1digit + 1, 10)) OR
    (sc.st_type = 'digit_minus_1' AND bd.machine_last_1digit = MOD(bd.date_last_1digit + 9, 10)) OR
    -- 特日条件（過去データの場合、店舗の特日タイプに応じて判定）
    (sc.st_type = 'special_day' AND (
      (bd.special_day_type = 'island' AND (
        EXTRACT(DAY FROM bd.target_date) IN (6, 16, 26) OR
        bd.target_date = LAST_DAY(bd.target_date)
      )) OR
      (bd.special_day_type = 'espas' AND (
        EXTRACT(DAY FROM bd.target_date) IN (6, 16, 26) OR
        EXTRACT(DAY FROM bd.target_date) = 14 OR
        bd.target_date = LAST_DAY(bd.target_date)
      ))
    )) OR
    (sc.st_type = 'non_special_day' AND (
      bd.special_day_type = 'none' OR
      (bd.special_day_type = 'island' AND NOT (
        EXTRACT(DAY FROM bd.target_date) IN (6, 16, 26) OR
        bd.target_date = LAST_DAY(bd.target_date)
      )) OR
      (bd.special_day_type = 'espas' AND NOT (
        EXTRACT(DAY FROM bd.target_date) IN (6, 16, 26) OR
        EXTRACT(DAY FROM bd.target_date) = 14 OR
        bd.target_date = LAST_DAY(bd.target_date)
      ))
    ))
),

-- ----------------------------------------------------------------------------
-- 3-3. 戦略ごとの実績集計（店舗・機種・メソッドごと）
-- ----------------------------------------------------------------------------
strategy_effectiveness AS (
  SELECT
    ss.target_hole,
    ss.target_machine,
    ss.special_day_type,
    ss.score_method,
    ss.strategy_name,
    COUNT(*) AS ref_count,
    COUNT(DISTINCT ss.target_date) AS days,
    AVG(CASE WHEN ss.next_diff > 0 THEN 1.0 ELSE 0.0 END) AS win_rate,
    AVG((ss.next_game * 3 + ss.next_diff) / NULLIF(ss.next_game * 3, 0)) AS payout_rate,
    -- 有効性スコア
    (
      -- 勝率パーセンタイルスコア
      CASE
        WHEN AVG(CASE WHEN ss.next_diff > 0 THEN 1.0 ELSE 0.0 END) >= 0.50 THEN 1.0
        WHEN AVG(CASE WHEN ss.next_diff > 0 THEN 1.0 ELSE 0.0 END) >= 0.429 THEN 0.5 + 0.5 * (AVG(CASE WHEN ss.next_diff > 0 THEN 1.0 ELSE 0.0 END) - 0.429) / (0.50 - 0.429)
        WHEN AVG(CASE WHEN ss.next_diff > 0 THEN 1.0 ELSE 0.0 END) >= 0.357 THEN 0.25 + 0.25 * (AVG(CASE WHEN ss.next_diff > 0 THEN 1.0 ELSE 0.0 END) - 0.357) / (0.429 - 0.357)
        ELSE 0.25 * AVG(CASE WHEN ss.next_diff > 0 THEN 1.0 ELSE 0.0 END) / 0.357
      END +
      -- 機械割パーセンタイルスコア
      CASE
        WHEN AVG((ss.next_game * 3 + ss.next_diff) / NULLIF(ss.next_game * 3, 0)) >= 1.0447 THEN 1.0
        WHEN AVG((ss.next_game * 3 + ss.next_diff) / NULLIF(ss.next_game * 3, 0)) >= 1.0247 THEN 0.5 + 0.5 * (AVG((ss.next_game * 3 + ss.next_diff) / NULLIF(ss.next_game * 3, 0)) - 1.0247) / (1.0447 - 1.0247)
        WHEN AVG((ss.next_game * 3 + ss.next_diff) / NULLIF(ss.next_game * 3, 0)) >= 1.0091 THEN 0.25 + 0.25 * (AVG((ss.next_game * 3 + ss.next_diff) / NULLIF(ss.next_game * 3, 0)) - 1.0091) / (1.0247 - 1.0091)
        ELSE 0.25 * AVG((ss.next_game * 3 + ss.next_diff) / NULLIF(ss.next_game * 3, 0)) / 1.0091
      END
    ) / 2.0 AS effectiveness
  FROM strategy_simulation ss
  WHERE ss.next_game IS NOT NULL
  GROUP BY ss.target_hole, ss.target_machine, ss.special_day_type, ss.score_method, ss.strategy_name
),

-- ----------------------------------------------------------------------------
-- 3-4. 有効性スコアでフィルタリングした戦略（rms_frequency_filter用）
-- ----------------------------------------------------------------------------
strategy_effectiveness_filtered AS (
  SELECT 
    target_hole,
    target_machine,
    special_day_type,
    score_method,
    strategy_name,
    ref_count,
    days,
    win_rate,
    payout_rate,
    effectiveness
  FROM strategy_effectiveness
  WHERE effectiveness >= 0.5
),

-- ############################################################################
-- Part 4: 推奨対象日の台ごとのスコア計算
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 4-1. 推奨対象日の台が該当する戦略を特定
-- ----------------------------------------------------------------------------
next_day_matches AS (
  SELECT
    cd.target_hole,
    cd.target_machine,
    cd.special_day_type,
    cd.score_method,
    ndi.next_date,
    cd.machine_number,
    sc.strategy_name
  FROM current_data cd
  INNER JOIN next_day_info ndi
    ON cd.target_hole = ndi.target_hole
    AND cd.target_machine = ndi.target_machine
    AND cd.score_method = ndi.score_method
  CROSS JOIN strategy_combinations sc
  WHERE
    -- 長期条件の評価
    (sc.lt_type = 'none') OR
    (sc.lt_type = 'win_rate' AND sc.lt_op = '>=' AND sc.lt_threshold_upper IS NULL AND cd.prev_d28_win_rate >= sc.lt_threshold) OR
    (sc.lt_type = 'win_rate' AND sc.lt_op = '>=' AND sc.lt_threshold_upper IS NOT NULL AND cd.prev_d28_win_rate >= sc.lt_threshold AND cd.prev_d28_win_rate < sc.lt_threshold_upper) OR
    (sc.lt_type = 'win_rate' AND sc.lt_op = '<' AND cd.prev_d28_win_rate < sc.lt_threshold) OR
    (sc.lt_type = 'payout_rate' AND sc.lt_op = '>=' AND sc.lt_threshold_upper IS NULL AND cd.prev_d28_payout_rate >= sc.lt_threshold) OR
    (sc.lt_type = 'payout_rate' AND sc.lt_op = '>=' AND sc.lt_threshold_upper IS NOT NULL AND cd.prev_d28_payout_rate >= sc.lt_threshold AND cd.prev_d28_payout_rate < sc.lt_threshold_upper) OR
    (sc.lt_type = 'payout_rate' AND sc.lt_op = '<' AND cd.prev_d28_payout_rate < sc.lt_threshold) OR
    (sc.lt_type = 'diff_rank' AND sc.lt_rank_type = 'best' AND sc.lt_rank_range = '1-5' AND cd.prev_d28_rank_best <= 5) OR
    (sc.lt_type = 'diff_rank' AND sc.lt_rank_type = 'best' AND sc.lt_rank_range = '6-10' AND cd.prev_d28_rank_best BETWEEN 6 AND 10) OR
    (sc.lt_type = 'diff_rank' AND sc.lt_rank_type = 'worst' AND sc.lt_rank_range = '1-5' AND cd.prev_d28_rank_worst <= 5) OR
    (sc.lt_type = 'diff_rank' AND sc.lt_rank_type = 'worst' AND sc.lt_rank_range = '6-10' AND cd.prev_d28_rank_worst BETWEEN 6 AND 10)
  AND
    -- 短期条件の評価（推奨日の日付で評価、評価クエリと同じロジック）
    (sc.st_type = 'none') OR
    -- 勝率100%（>= 1.0 AND <= 1.0）
    (sc.st_type = 'win_rate' AND sc.st_op = '>=' AND sc.st_threshold = 1.0 AND sc.st_threshold_upper = 1.0 AND (
      (sc.st_period = 3 AND cd.prev_d3_win_rate = 1.0) OR
      (sc.st_period = 5 AND cd.prev_d5_win_rate = 1.0) OR
      (sc.st_period = 7 AND cd.prev_d7_win_rate = 1.0)
    )) OR
    -- 勝率0%（>= 0.0 AND <= 0.0）
    (sc.st_type = 'win_rate' AND sc.st_op = '>=' AND sc.st_threshold = 0.0 AND sc.st_threshold_upper = 0.0 AND (
      (sc.st_period = 3 AND cd.prev_d3_win_rate = 0.0) OR
      (sc.st_period = 5 AND cd.prev_d5_win_rate = 0.0) OR
      (sc.st_period = 7 AND cd.prev_d7_win_rate = 0.0)
    )) OR
    -- 勝率範囲（> threshold AND < upper または <= upper）
    (sc.st_type = 'win_rate' AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND (
      (sc.st_period = 3 AND cd.prev_d3_win_rate > sc.st_threshold AND cd.prev_d3_win_rate < sc.st_threshold_upper) OR
      (sc.st_period = 5 AND cd.prev_d5_win_rate > sc.st_threshold AND cd.prev_d5_win_rate < sc.st_threshold_upper) OR
      (sc.st_period = 7 AND cd.prev_d7_win_rate > sc.st_threshold AND cd.prev_d7_win_rate < sc.st_threshold_upper) OR
      -- 50%超75%以下の場合は <= を使用
      (sc.st_threshold = 0.5 AND sc.st_period = 3 AND cd.prev_d3_win_rate > sc.st_threshold AND cd.prev_d3_win_rate <= sc.st_threshold_upper) OR
      (sc.st_threshold = 0.5 AND sc.st_period = 5 AND cd.prev_d5_win_rate > sc.st_threshold AND cd.prev_d5_win_rate <= sc.st_threshold_upper) OR
      (sc.st_threshold = 0.5 AND sc.st_period = 7 AND cd.prev_d7_win_rate > sc.st_threshold AND cd.prev_d7_win_rate <= sc.st_threshold_upper)
    )) OR
    (sc.st_type = 'digit_match_1' AND cd.machine_last_1digit = ndi.next_date_last_1digit) OR
    (sc.st_type = 'digit_match_2' AND cd.machine_last_2digits = ndi.next_date_last_2digits) OR
    (sc.st_type = 'digit_plus_1' AND cd.machine_last_1digit = MOD(ndi.next_date_last_1digit + 1, 10)) OR
    (sc.st_type = 'digit_minus_1' AND cd.machine_last_1digit = MOD(ndi.next_date_last_1digit + 9, 10)) OR
    -- 特日条件
    (sc.st_type = 'special_day' AND ndi.next_is_special_day = TRUE) OR
    (sc.st_type = 'non_special_day' AND ndi.next_is_special_day = FALSE)
),

-- ----------------------------------------------------------------------------
-- 4-2. 台ごとのスコア計算
-- ----------------------------------------------------------------------------
-- 通常版（全戦略を使用）
machine_scores_all AS (
  SELECT
    ndm.target_hole,
    ndm.target_machine,
    ndm.special_day_type,
    ndm.score_method,
    ndm.next_date,
    ndm.machine_number,
    COUNT(DISTINCT ndm.strategy_name) AS match_count,
    SUM(COALESCE(se.ref_count, 1) * COALESCE(se.effectiveness, 1.0)) AS total_weight,
    SUM(COALESCE(se.ref_count, 1) * COALESCE(se.effectiveness, 1.0) * COALESCE(se.payout_rate, 0)) AS weighted_payout_sum,
    SUM(COALESCE(se.ref_count, 1) * COALESCE(se.effectiveness, 1.0) * COALESCE(se.win_rate, 0)) AS weighted_win_sum,
    SUM(COALESCE(se.days, 0)) AS total_days,
    SUM(COALESCE(se.ref_count, 0)) AS total_ref_count
  FROM next_day_matches ndm
  LEFT JOIN strategy_effectiveness se 
    ON ndm.target_hole = se.target_hole
    AND ndm.target_machine = se.target_machine
    AND ndm.score_method = se.score_method
    AND ndm.strategy_name = se.strategy_name
  GROUP BY ndm.target_hole, ndm.target_machine, ndm.special_day_type, ndm.score_method, ndm.next_date, ndm.machine_number
),

-- フィルタリング版（有効性スコア0.5以上の戦略のみ、rms_frequency_filter用）
machine_scores_filtered AS (
  SELECT
    ndm.target_hole,
    ndm.target_machine,
    ndm.special_day_type,
    ndm.score_method,
    ndm.next_date,
    ndm.machine_number,
    COUNT(DISTINCT ndm.strategy_name) AS match_count,
    SUM(COALESCE(sef.ref_count, 1) * COALESCE(sef.effectiveness, 1.0)) AS total_weight,
    SUM(COALESCE(sef.ref_count, 1) * COALESCE(sef.effectiveness, 1.0) * COALESCE(sef.payout_rate, 0)) AS weighted_payout_sum,
    SUM(COALESCE(sef.ref_count, 1) * COALESCE(sef.effectiveness, 1.0) * COALESCE(sef.win_rate, 0)) AS weighted_win_sum,
    SUM(COALESCE(sef.days, 0)) AS total_days,
    SUM(COALESCE(sef.ref_count, 0)) AS total_ref_count
  FROM next_day_matches ndm
  INNER JOIN strategy_effectiveness_filtered sef 
    ON ndm.target_hole = sef.target_hole
    AND ndm.target_machine = sef.target_machine
    AND ndm.score_method = sef.score_method
    AND ndm.strategy_name = sef.strategy_name
  GROUP BY ndm.target_hole, ndm.target_machine, ndm.special_day_type, ndm.score_method, ndm.next_date, ndm.machine_number
),

-- score_methodに応じて使用するテーブルを選択（各組み合わせごと）
machine_scores AS (
  SELECT * FROM machine_scores_all
  WHERE score_method NOT IN ('rms_frequency_filter')
  UNION ALL
  SELECT * FROM machine_scores_filtered
  WHERE score_method IN ('rms_frequency_filter')
),

-- ----------------------------------------------------------------------------
-- 4-3. 最大値の計算（正規化用、店舗・機種・メソッドごと）
-- ----------------------------------------------------------------------------
max_values AS (
  SELECT
    ms.target_hole,
    ms.target_machine,
    ms.special_day_type,
    ms.score_method,
    MAX(ms.match_count) AS max_match_count,
    MAX(ms.total_days + ms.total_ref_count) AS max_days_ref_count
  FROM machine_scores ms
  GROUP BY ms.target_hole, ms.target_machine, ms.special_day_type, ms.score_method
),

-- ----------------------------------------------------------------------------
-- 4-4. スコア詳細計算
-- ----------------------------------------------------------------------------
score_details AS (
  SELECT
    ms.target_hole,
    ms.target_machine,
    ms.special_day_type,
    ms.score_method,
    ms.next_date AS target_date,
    ms.machine_number,
    ms.match_count,
    -- 重み付け平均
    CASE WHEN ms.total_weight > 0 THEN ms.weighted_payout_sum / ms.total_weight ELSE 0 END AS weighted_payout_rate,
    CASE WHEN ms.total_weight > 0 THEN ms.weighted_win_sum / ms.total_weight ELSE 0 END AS weighted_win_rate,
    -- パーセンタイルスコア（勝率）
    CASE
      WHEN ms.total_weight > 0 AND ms.weighted_win_sum / ms.total_weight >= 0.50 THEN 1.0
      WHEN ms.total_weight > 0 AND ms.weighted_win_sum / ms.total_weight >= 0.429 
        THEN 0.5 + 0.5 * ((ms.weighted_win_sum / ms.total_weight) - 0.429) / (0.50 - 0.429)
      WHEN ms.total_weight > 0 AND ms.weighted_win_sum / ms.total_weight >= 0.357 
        THEN 0.25 + 0.25 * ((ms.weighted_win_sum / ms.total_weight) - 0.357) / (0.429 - 0.357)
      ELSE GREATEST(0, 0.25 * CASE WHEN ms.total_weight > 0 THEN (ms.weighted_win_sum / ms.total_weight) / 0.357 ELSE 0 END)
    END AS win_rate_percentile,
    -- パーセンタイルスコア（機械割）
    CASE
      WHEN ms.total_weight > 0 AND ms.weighted_payout_sum / ms.total_weight >= 1.0447 THEN 1.0
      WHEN ms.total_weight > 0 AND ms.weighted_payout_sum / ms.total_weight >= 1.0247 
        THEN 0.5 + 0.5 * ((ms.weighted_payout_sum / ms.total_weight) - 1.0247) / (1.0447 - 1.0247)
      WHEN ms.total_weight > 0 AND ms.weighted_payout_sum / ms.total_weight >= 1.0091 
        THEN 0.25 + 0.25 * ((ms.weighted_payout_sum / ms.total_weight) - 1.0091) / (1.0247 - 1.0091)
      ELSE GREATEST(0, 0.25 * CASE WHEN ms.total_weight > 0 THEN (ms.weighted_payout_sum / ms.total_weight) / 1.0091 ELSE 0 END)
    END AS payout_rate_percentile,
    -- 出現頻度ボーナス
    CASE 
      WHEN mv.max_match_count > 0 THEN LEAST(SQRT(ms.match_count) / SQRT(mv.max_match_count), 1.0)
      ELSE 1.0
    END AS frequency_bonus,
    -- 信頼性スコア（絶対閾値ベース）
    CASE 
      WHEN (ms.total_days >= 30 AND ms.total_ref_count >= 50) THEN 1.0
      WHEN (ms.total_days >= 20 AND ms.total_ref_count >= 30) THEN 0.8
      WHEN (ms.total_days >= 10 AND ms.total_ref_count >= 20) THEN 0.6
      ELSE 0.4
    END AS reliability_score,
    -- 異常値ボーナス
    CASE
      WHEN ms.total_weight > 0 
        AND ms.weighted_payout_sum / ms.total_weight > 1.0447 * 1.05 
        AND ms.weighted_win_sum / ms.total_weight > 0.50 * 1.1 THEN 1.1 * 1.1
      WHEN ms.total_weight > 0 
        AND ms.weighted_payout_sum / ms.total_weight > 1.0447 * 1.05 THEN 1.1
      WHEN ms.total_weight > 0 
        AND ms.weighted_win_sum / ms.total_weight > 0.50 * 1.1 THEN 1.1
      ELSE 1.0
    END AS anomaly_bonus,
    -- 複合ボーナス
    CASE
      WHEN ms.total_weight > 0 
        AND ms.weighted_payout_sum / ms.total_weight >= 1.0247 
        AND ms.weighted_win_sum / ms.total_weight >= 0.429 THEN 1.1
      ELSE 1.0
    END AS dual_high_bonus,
    ms.total_days,
    ms.total_ref_count
  FROM machine_scores ms
  INNER JOIN max_values mv
    ON ms.target_hole = mv.target_hole
    AND ms.target_machine = mv.target_machine
    AND ms.score_method = mv.score_method
),

-- ----------------------------------------------------------------------------
-- 4-5. 総合スコア計算（score_methodに応じて切り替え）
-- ----------------------------------------------------------------------------
final_scores AS (
  SELECT
    sd.target_hole,
    sd.target_machine,
    sd.special_day_type,
    sd.score_method,
    sd.target_date,
    sd.machine_number,
    sd.match_count,
    sd.weighted_payout_rate,
    sd.weighted_win_rate,
    -- RMS
    SQRT((sd.win_rate_percentile * sd.win_rate_percentile + sd.payout_rate_percentile * sd.payout_rate_percentile) / 2) AS rms,
    sd.frequency_bonus,
    sd.reliability_score,
    sd.anomaly_bonus,
    sd.dual_high_bonus,
    sd.total_days,
    sd.total_ref_count,
    -- 総合スコア（score_methodに応じて切り替え）
    CASE sd.score_method
      -- 改善案1: RMSのみ（シンプル化）
      WHEN 'simple' THEN 
        SQRT((sd.win_rate_percentile * sd.win_rate_percentile + sd.payout_rate_percentile * sd.payout_rate_percentile) / 2)
      -- 改善案2: RMS × 信頼性（絶対閾値ベース）
      WHEN 'rms_reliability' THEN 
        SQRT((sd.win_rate_percentile * sd.win_rate_percentile + sd.payout_rate_percentile * sd.payout_rate_percentile) / 2)
        * sd.reliability_score
      -- 改善案3: RMS × 頻度ボーナス
      WHEN 'rms_frequency' THEN 
        SQRT((sd.win_rate_percentile * sd.win_rate_percentile + sd.payout_rate_percentile * sd.payout_rate_percentile) / 2)
        * sd.frequency_bonus
      -- ハイブリッド案1: RMS × 頻度（有効性スコア0.5以上の戦略のみ使用）
      WHEN 'rms_frequency_filter' THEN 
        SQRT((sd.win_rate_percentile * sd.win_rate_percentile + sd.payout_rate_percentile * sd.payout_rate_percentile) / 2)
        * sd.frequency_bonus
      -- ハイブリッド案2: RMS × 頻度 × 異常値ボーナス
      WHEN 'rms_frequency_anomaly' THEN 
        SQRT((sd.win_rate_percentile * sd.win_rate_percentile + sd.payout_rate_percentile * sd.payout_rate_percentile) / 2)
        * sd.frequency_bonus * sd.anomaly_bonus
      -- ハイブリッド案3: RMS × 頻度 × 複合ボーナス
      WHEN 'rms_frequency_dual' THEN 
        SQRT((sd.win_rate_percentile * sd.win_rate_percentile + sd.payout_rate_percentile * sd.payout_rate_percentile) / 2)
        * sd.frequency_bonus * sd.dual_high_bonus
      -- 元の計算方法（original）
      ELSE 
        SQRT((sd.win_rate_percentile * sd.win_rate_percentile + sd.payout_rate_percentile * sd.payout_rate_percentile) / 2)
        * sd.reliability_score * sd.frequency_bonus * sd.anomaly_bonus * sd.dual_high_bonus
    END AS total_score
  FROM score_details sd
),

-- ----------------------------------------------------------------------------
-- 4-6. TOP1スコアとランキング（店舗・機種・メソッドごと）
-- ----------------------------------------------------------------------------
ranked_scores AS (
  SELECT
    fs.target_hole,
    fs.target_machine,
    fs.special_day_type,
    fs.score_method,
    fs.target_date,
    fs.machine_number,
    fs.match_count,
    fs.weighted_payout_rate,
    fs.weighted_win_rate,
    fs.rms,
    fs.frequency_bonus,
    fs.reliability_score,
    fs.anomaly_bonus,
    fs.dual_high_bonus,
    fs.total_score,
    MAX(fs.total_score) OVER (PARTITION BY fs.target_hole, fs.target_machine, fs.score_method) AS top1_score,
    fs.total_score / NULLIF(MAX(fs.total_score) OVER (PARTITION BY fs.target_hole, fs.target_machine, fs.score_method), 0) AS top1_ratio,
    ROW_NUMBER() OVER (PARTITION BY fs.target_hole, fs.target_machine, fs.score_method ORDER BY fs.total_score DESC) AS rank
  FROM final_scores fs
)

-- ############################################################################
-- Part 5: 最終出力
-- ############################################################################
SELECT
  rs.target_hole AS hole_name,
  rs.target_machine AS machine_name,
  rs.score_method,
  rs.target_date,
  rs.machine_number,
  -- 優先度ランク（5=最高、0=対象外）
  CASE
    WHEN rs.top1_ratio >= 0.99 THEN 5
    WHEN rs.top1_ratio >= 0.97 THEN 4
    WHEN rs.top1_ratio >= 0.95 THEN 3
    WHEN rs.top1_ratio >= 0.90 THEN 2
    WHEN rs.top1_ratio >= 0.80 THEN 1
    ELSE 0
  END AS priority_rank,
  rs.total_score,
  rs.top1_ratio,
  rs.rank,
  rs.match_count,
  rs.weighted_payout_rate,
  rs.weighted_win_rate,
  rs.rms,
  rs.frequency_bonus,
  rs.reliability_score,
  rs.anomaly_bonus,
  rs.dual_high_bonus,
  rs.top1_score
FROM ranked_scores rs
ORDER BY rs.target_hole, rs.target_machine, rs.score_method, rs.rank

