-- ============================================================================
-- 狙い台一覧出力クエリ
-- ============================================================================
-- 
-- 【概要】
--   tolove_recommendation.sql のロジックを使用して、最終的な「狙い台一覧」を出力する。
--   スコア計算（rms_frequency_dual）と優先度ランク付けまでSQLで完結。
--   GASはこの結果をスプレッドシートに出力・整形するだけ。
--
-- 【出力項目】
--   - target_date: 推奨日付
--   - machine_number: 台番
--   - priority_rank: 優先度ランク（5=最高、1=最低、0=対象外）
--   - total_score: 総合スコア
--   - top1_ratio: TOP1スコアとの比率（0〜1）
--   - match_count: 該当戦略数
--   - weighted_payout_rate: 重み付け機械割（0〜1、例: 1.085 = 108.5%）
--   - weighted_win_rate: 重み付け勝率（0〜1、例: 0.583 = 58.3%）
--   - rms: RMSスコア
--   - frequency_bonus: 出現頻度ボーナス
--   - dual_high_bonus: 複合ボーナス
--
-- 【優先度ランクの定義】
--   5: TOP1スコアの99%以上 → 勝率63%, 機械割113%期待
--   4: TOP1スコアの97%以上 → 勝率60%, 機械割110%期待
--   3: TOP1スコアの95%以上 → 勝率56%, 機械割108%期待
--   2: TOP1スコアの90%以上 → 勝率50%, 機械割106%期待
--   1: TOP1スコアの80%以上 → 参考程度
--   0: それ以外
--
-- 【パラメータ定義】
-- ============================================================================
-- ★★★ BigQuery Connector で使用する場合 ★★★
-- BigQuery Connector は DECLARE 文をサポートしていないため、
-- 以下の params CTE 内の値を直接変更してください。
--
-- ★★★ BigQuery コンソールで使用する場合 ★★★
-- DECLARE 文のコメントを外して使用することもできます。
-- ============================================================================
-- DECLARE target_date DATE DEFAULT NULL;  -- 推奨台を出す日付（NULL=最新日の次の日）
-- DECLARE target_hole STRING DEFAULT 'アイランド秋葉原店';  -- 対象店舗
-- DECLARE target_machine STRING DEFAULT 'L+ToLOVEるダークネス';  -- 対象機種

-- 【パーセンタイル閾値】
-- ============================================================================
-- 勝率（過去28日間）: P25=0.357, P50=0.429, P75=0.50
-- 機械割（過去28日間）: P25=1.0091, P50=1.0247, P75=1.0447

WITH

-- ############################################################################
-- Part 0: パラメータ定義（BigQuery Connector 用）
-- ############################################################################
-- ★★★ 対象店舗・機種を変更する場合は、ここを編集してください ★★★
params AS (
  SELECT
    CAST(NULL AS DATE) AS target_date,  -- 推奨台を出す日付（NULL=最新日の次の日）
    'アイランド秋葉原店' AS target_hole,  -- 対象店舗
    'L+ToLOVEるダークネス' AS target_machine  -- 対象機種
),

-- ############################################################################
-- Part 1: 基本データの取得
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 1-1. 対象日付の決定
-- ----------------------------------------------------------------------------
target_date_calc AS (
  SELECT
    CASE
      WHEN p.target_date IS NOT NULL THEN p.target_date
      ELSE (
        SELECT DATE_ADD(MAX(ms.target_date), INTERVAL 1 DAY)
        FROM `yobun-450512.datamart.machine_stats` ms, params p2
        WHERE ms.hole = p2.target_hole AND ms.machine = p2.target_machine
      )
    END AS calc_target_date,
    p.target_hole,
    p.target_machine
  FROM params p
),

-- ----------------------------------------------------------------------------
-- 1-2. 基本データの取得
-- ----------------------------------------------------------------------------
base_data AS (
  SELECT
    ms.target_date,
    ms.machine_number,
    ms.hole AS hole_name,
    ms.machine AS machine_name,
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
    -- 差枚ランキング（当日基準）
    ROW_NUMBER() OVER (PARTITION BY ms.target_date ORDER BY ms.prev_d28_diff DESC) AS prev_d28_rank_best,
    ROW_NUMBER() OVER (PARTITION BY ms.target_date ORDER BY ms.prev_d28_diff ASC) AS prev_d28_rank_worst
  FROM `yobun-450512.datamart.machine_stats` ms
  CROSS JOIN params p
  WHERE ms.hole = p.target_hole
    AND ms.machine = p.target_machine
),

-- ----------------------------------------------------------------------------
-- 1-3. 推奨対象日の情報
-- ----------------------------------------------------------------------------
next_day_info AS (
  SELECT
    tdc.calc_target_date AS next_date,
    MOD(EXTRACT(DAY FROM tdc.calc_target_date), 10) AS next_date_last_1digit,
    EXTRACT(DAY FROM tdc.calc_target_date) AS next_date_last_2digits
  FROM target_date_calc tdc
),

-- ----------------------------------------------------------------------------
-- 1-4. 推奨対象日の前日を取得
-- ----------------------------------------------------------------------------
prev_day AS (
  SELECT DATE_SUB(calc_target_date, INTERVAL 1 DAY) AS prev_date
  FROM target_date_calc
),

-- ----------------------------------------------------------------------------
-- 1-5. 最新データ（推奨対象日の前日データのみ）
-- ----------------------------------------------------------------------------
-- ★★★ 台番号の入れ替えを考慮 ★★★
-- 「推奨対象日の前日」に存在する台番号のみを対象にする
-- これにより、過去に別の機種だった台番号（現在は存在しない）を除外
current_data AS (
  SELECT
    bd.*
  FROM base_data bd
  CROSS JOIN prev_day pd
  WHERE bd.target_date = pd.prev_date
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
    STRUCT('過去28日間勝率50.0%以上', 'win_rate', 0.50, CAST(NULL AS FLOAT64), '>=', CAST(NULL AS STRING), CAST(NULL AS STRING), 1),
    STRUCT('過去28日間勝率42.9%以上50.0%未満', 'win_rate', 0.429, 0.50, '>=', CAST(NULL AS STRING), CAST(NULL AS STRING), 2),
    STRUCT('過去28日間勝率35.7%以上42.9%未満', 'win_rate', 0.357, 0.429, '>=', CAST(NULL AS STRING), CAST(NULL AS STRING), 3),
    STRUCT('過去28日間勝率35.7%未満', 'win_rate', 0.357, CAST(NULL AS FLOAT64), '<', CAST(NULL AS STRING), CAST(NULL AS STRING), 4),
    -- 過去28日間機械割（パーセンタイルベース）
    STRUCT('過去28日間機械割104.47%以上', 'payout_rate', 1.0447, CAST(NULL AS FLOAT64), '>=', CAST(NULL AS STRING), CAST(NULL AS STRING), 5),
    STRUCT('過去28日間機械割102.47%以上104.47%未満', 'payout_rate', 1.0247, 1.0447, '>=', CAST(NULL AS STRING), CAST(NULL AS STRING), 6),
    STRUCT('過去28日間機械割100.91%以上102.47%未満', 'payout_rate', 1.0091, 1.0247, '>=', CAST(NULL AS STRING), CAST(NULL AS STRING), 7),
    STRUCT('過去28日間機械割100.91%未満', 'payout_rate', 1.0091, CAST(NULL AS FLOAT64), '<', CAST(NULL AS STRING), CAST(NULL AS STRING), 8),
    -- 過去28日間差枚（ランキングベース）
    STRUCT('過去28日間差枚ベスト1~5', 'diff_rank', CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS STRING), 'best', '1-5', 9),
    STRUCT('過去28日間差枚ベスト6~10', 'diff_rank', CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS STRING), 'best', '6-10', 10),
    STRUCT('過去28日間差枚ワースト1~5', 'diff_rank', CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS STRING), 'worst', '1-5', 11),
    STRUCT('過去28日間差枚ワースト6~10', 'diff_rank', CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS STRING), 'worst', '6-10', 12)
  ])
),

-- ----------------------------------------------------------------------------
-- 2-2. 短期条件マスタ（勝率）
-- ----------------------------------------------------------------------------
short_term_win_rate_conditions AS (
  SELECT * FROM UNNEST([
    STRUCT('条件なし' AS st_name, 'none' AS st_type, 0 AS st_period, CAST(NULL AS FLOAT64) AS st_threshold, CAST(NULL AS FLOAT64) AS st_threshold_upper, CAST(NULL AS STRING) AS st_op, 0 AS st_sort),
    -- 過去3日間勝率
    STRUCT('過去3日間勝率100%', 'win_rate', 3, 1.0, CAST(NULL AS FLOAT64), '=', 1),
    STRUCT('過去3日間勝率75%超100%未満', 'win_rate', 3, 0.75, 1.0, '>', 2),
    STRUCT('過去3日間勝率50%超75%以下', 'win_rate', 3, 0.50, 0.75, '>', 3),
    STRUCT('過去3日間勝率25%超50%以下', 'win_rate', 3, 0.25, 0.50, '>', 4),
    STRUCT('過去3日間勝率0%超25%未満', 'win_rate', 3, 0.0, 0.25, '>', 5),
    STRUCT('過去3日間勝率0%', 'win_rate', 3, 0.0, CAST(NULL AS FLOAT64), '=', 6),
    -- 過去5日間勝率
    STRUCT('過去5日間勝率100%', 'win_rate', 5, 1.0, CAST(NULL AS FLOAT64), '=', 7),
    STRUCT('過去5日間勝率75%超100%未満', 'win_rate', 5, 0.75, 1.0, '>', 8),
    STRUCT('過去5日間勝率50%超75%以下', 'win_rate', 5, 0.50, 0.75, '>', 9),
    STRUCT('過去5日間勝率25%超50%以下', 'win_rate', 5, 0.25, 0.50, '>', 10),
    STRUCT('過去5日間勝率0%超25%未満', 'win_rate', 5, 0.0, 0.25, '>', 11),
    STRUCT('過去5日間勝率0%', 'win_rate', 5, 0.0, CAST(NULL AS FLOAT64), '=', 12),
    -- 過去7日間勝率
    STRUCT('過去7日間勝率100%', 'win_rate', 7, 1.0, CAST(NULL AS FLOAT64), '=', 13),
    STRUCT('過去7日間勝率75%超100%未満', 'win_rate', 7, 0.75, 1.0, '>', 14),
    STRUCT('過去7日間勝率50%超75%以下', 'win_rate', 7, 0.50, 0.75, '>', 15),
    STRUCT('過去7日間勝率25%超50%以下', 'win_rate', 7, 0.25, 0.50, '>', 16),
    STRUCT('過去7日間勝率0%超25%未満', 'win_rate', 7, 0.0, 0.25, '>', 17),
    STRUCT('過去7日間勝率0%', 'win_rate', 7, 0.0, CAST(NULL AS FLOAT64), '=', 18)
  ])
),

-- ----------------------------------------------------------------------------
-- 2-3. 短期条件マスタ（末尾関連性）
-- ----------------------------------------------------------------------------
short_term_digit_conditions AS (
  SELECT * FROM UNNEST([
    STRUCT('台番末尾1桁=日付末尾1桁' AS st_name, 'digit_match_1' AS st_type, 0 AS st_period, CAST(NULL AS FLOAT64) AS st_threshold, CAST(NULL AS FLOAT64) AS st_threshold_upper, CAST(NULL AS STRING) AS st_op, 19 AS st_sort),
    STRUCT('台番末尾2桁=日付末尾2桁', 'digit_match_2', 0, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS STRING), 20),
    STRUCT('台番末尾1桁=日付末尾1桁+1', 'digit_plus_1', 0, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS STRING), 21),
    STRUCT('台番末尾1桁=日付末尾1桁-1', 'digit_minus_1', 0, CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64), CAST(NULL AS STRING), 22)
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
      WHEN lt.lt_type = 'none' AND st.st_type = 'none' THEN '全条件なし'
      WHEN lt.lt_type = 'none' THEN st.st_name
      WHEN st.st_type = 'none' THEN lt.lt_name
      ELSE CONCAT(lt.lt_name, '+', st.st_name)
    END AS strategy_name,
    lt.lt_name, lt.lt_type, lt.lt_threshold, lt.lt_threshold_upper, lt.lt_op, lt.lt_rank_type, lt.lt_rank_range, lt.lt_sort,
    st.st_name, st.st_type, st.st_period, st.st_threshold, st.st_threshold_upper, st.st_op, st.st_sort
  FROM long_term_conditions lt
  CROSS JOIN short_term_conditions st
  WHERE NOT (
    lt.lt_type != 'none' AND st.st_type IN ('digit_match_1', 'digit_match_2', 'digit_plus_1', 'digit_minus_1')
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
  SELECT DISTINCT machine_number
  FROM current_data
),

-- ----------------------------------------------------------------------------
-- 3-2. 過去データでの戦略シミュレーション（現在の台番号のみ）
-- ----------------------------------------------------------------------------
strategy_simulation AS (
  SELECT
    bd.target_date,
    bd.machine_number,
    sc.strategy_name,
    sc.lt_type,
    sc.st_type,
    -- 次の日のパフォーマンス
    LEAD(bd.d1_diff) OVER (PARTITION BY bd.machine_number ORDER BY bd.target_date) AS next_diff,
    LEAD(bd.d1_game) OVER (PARTITION BY bd.machine_number ORDER BY bd.target_date) AS next_game
  FROM base_data bd
  -- ★★★ 現在の台番号のみを対象（台番号入れ替えを考慮）★★★
  INNER JOIN current_machine_numbers cmn ON bd.machine_number = cmn.machine_number
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
    -- 短期条件の評価
    (sc.st_type = 'none') OR
    (sc.st_type = 'win_rate' AND sc.st_period = 3 AND sc.st_op = '=' AND bd.prev_d3_win_rate = sc.st_threshold) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 3 AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND bd.prev_d3_win_rate > sc.st_threshold AND bd.prev_d3_win_rate < sc.st_threshold_upper) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 3 AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND sc.st_threshold = 0.50 AND bd.prev_d3_win_rate > sc.st_threshold AND bd.prev_d3_win_rate <= sc.st_threshold_upper) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 5 AND sc.st_op = '=' AND bd.prev_d5_win_rate = sc.st_threshold) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 5 AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND bd.prev_d5_win_rate > sc.st_threshold AND bd.prev_d5_win_rate < sc.st_threshold_upper) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 5 AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND sc.st_threshold = 0.50 AND bd.prev_d5_win_rate > sc.st_threshold AND bd.prev_d5_win_rate <= sc.st_threshold_upper) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 7 AND sc.st_op = '=' AND bd.prev_d7_win_rate = sc.st_threshold) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 7 AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND bd.prev_d7_win_rate > sc.st_threshold AND bd.prev_d7_win_rate < sc.st_threshold_upper) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 7 AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND sc.st_threshold = 0.50 AND bd.prev_d7_win_rate > sc.st_threshold AND bd.prev_d7_win_rate <= sc.st_threshold_upper) OR
    (sc.st_type = 'digit_match_1' AND bd.machine_last_1digit = bd.date_last_1digit) OR
    (sc.st_type = 'digit_match_2' AND bd.machine_last_2digits = bd.date_last_2digits) OR
    (sc.st_type = 'digit_plus_1' AND bd.machine_last_1digit = MOD(bd.date_last_1digit + 1, 10)) OR
    (sc.st_type = 'digit_minus_1' AND bd.machine_last_1digit = MOD(bd.date_last_1digit + 9, 10))
),

-- ----------------------------------------------------------------------------
-- 3-2. 戦略ごとの実績集計
-- ----------------------------------------------------------------------------
strategy_effectiveness AS (
  SELECT
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
  GROUP BY ss.strategy_name
),

-- ############################################################################
-- Part 4: 推奨対象日の台ごとのスコア計算
-- ############################################################################

-- ----------------------------------------------------------------------------
-- 4-1. 推奨対象日の台が該当する戦略を特定
-- ----------------------------------------------------------------------------
next_day_matches AS (
  SELECT
    ndi.next_date,
    cd.machine_number,
    sc.strategy_name
  FROM current_data cd
  CROSS JOIN next_day_info ndi
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
    -- 短期条件の評価（推奨日の日付で評価）
    (sc.st_type = 'none') OR
    (sc.st_type = 'win_rate' AND sc.st_period = 3 AND sc.st_op = '=' AND cd.prev_d3_win_rate = sc.st_threshold) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 3 AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND cd.prev_d3_win_rate > sc.st_threshold AND cd.prev_d3_win_rate < sc.st_threshold_upper) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 3 AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND sc.st_threshold = 0.50 AND cd.prev_d3_win_rate > sc.st_threshold AND cd.prev_d3_win_rate <= sc.st_threshold_upper) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 5 AND sc.st_op = '=' AND cd.prev_d5_win_rate = sc.st_threshold) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 5 AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND cd.prev_d5_win_rate > sc.st_threshold AND cd.prev_d5_win_rate < sc.st_threshold_upper) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 5 AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND sc.st_threshold = 0.50 AND cd.prev_d5_win_rate > sc.st_threshold AND cd.prev_d5_win_rate <= sc.st_threshold_upper) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 7 AND sc.st_op = '=' AND cd.prev_d7_win_rate = sc.st_threshold) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 7 AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND cd.prev_d7_win_rate > sc.st_threshold AND cd.prev_d7_win_rate < sc.st_threshold_upper) OR
    (sc.st_type = 'win_rate' AND sc.st_period = 7 AND sc.st_op = '>' AND sc.st_threshold_upper IS NOT NULL AND sc.st_threshold = 0.50 AND cd.prev_d7_win_rate > sc.st_threshold AND cd.prev_d7_win_rate <= sc.st_threshold_upper) OR
    (sc.st_type = 'digit_match_1' AND cd.machine_last_1digit = ndi.next_date_last_1digit) OR
    (sc.st_type = 'digit_match_2' AND cd.machine_last_2digits = ndi.next_date_last_2digits) OR
    (sc.st_type = 'digit_plus_1' AND cd.machine_last_1digit = MOD(ndi.next_date_last_1digit + 1, 10)) OR
    (sc.st_type = 'digit_minus_1' AND cd.machine_last_1digit = MOD(ndi.next_date_last_1digit + 9, 10))
),

-- ----------------------------------------------------------------------------
-- 4-2. 台ごとのスコア計算
-- ----------------------------------------------------------------------------
machine_scores AS (
  SELECT
    ndm.next_date,
    ndm.machine_number,
    COUNT(DISTINCT ndm.strategy_name) AS match_count,
    SUM(COALESCE(se.ref_count, 1) * COALESCE(se.effectiveness, 1.0)) AS total_weight,
    SUM(COALESCE(se.ref_count, 1) * COALESCE(se.effectiveness, 1.0) * COALESCE(se.payout_rate, 0)) AS weighted_payout_sum,
    SUM(COALESCE(se.ref_count, 1) * COALESCE(se.effectiveness, 1.0) * COALESCE(se.win_rate, 0)) AS weighted_win_sum,
    SUM(COALESCE(se.days, 0)) AS total_days,
    SUM(COALESCE(se.ref_count, 0)) AS total_ref_count
  FROM next_day_matches ndm
  LEFT JOIN strategy_effectiveness se ON ndm.strategy_name = se.strategy_name
  GROUP BY ndm.next_date, ndm.machine_number
),

-- ----------------------------------------------------------------------------
-- 4-3. 最大値の計算（正規化用）
-- ----------------------------------------------------------------------------
max_values AS (
  SELECT
    MAX(ms.match_count) AS max_match_count
  FROM machine_scores ms
),

-- ----------------------------------------------------------------------------
-- 4-4. スコア詳細計算
-- ----------------------------------------------------------------------------
score_details AS (
  SELECT
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
  CROSS JOIN max_values mv
),

-- ----------------------------------------------------------------------------
-- 4-5. 総合スコア計算（rms_frequency_dual）
-- ----------------------------------------------------------------------------
final_scores AS (
  SELECT
    sd.target_date,
    sd.machine_number,
    sd.match_count,
    sd.weighted_payout_rate,
    sd.weighted_win_rate,
    -- RMS
    SQRT((sd.win_rate_percentile * sd.win_rate_percentile + sd.payout_rate_percentile * sd.payout_rate_percentile) / 2) AS rms,
    sd.frequency_bonus,
    sd.dual_high_bonus,
    -- 総合スコア = RMS × 頻度ボーナス × 複合ボーナス
    SQRT((sd.win_rate_percentile * sd.win_rate_percentile + sd.payout_rate_percentile * sd.payout_rate_percentile) / 2) 
      * sd.frequency_bonus 
      * sd.dual_high_bonus AS total_score
  FROM score_details sd
),

-- ----------------------------------------------------------------------------
-- 4-6. TOP1スコアとランキング
-- ----------------------------------------------------------------------------
ranked_scores AS (
  SELECT
    fs.*,
    MAX(fs.total_score) OVER () AS top1_score,
    fs.total_score / NULLIF(MAX(fs.total_score) OVER (), 0) AS top1_ratio,
    ROW_NUMBER() OVER (ORDER BY fs.total_score DESC) AS rank
  FROM final_scores fs
)

-- ############################################################################
-- Part 5: 最終出力
-- ############################################################################
SELECT
  p.target_hole AS hole_name,
  p.target_machine AS machine_name,
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
  rs.dual_high_bonus,
  rs.top1_score
FROM ranked_scores rs
CROSS JOIN params p
ORDER BY rs.rank

