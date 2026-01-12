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
--   基本戦略（単一期間参照）:
--     - 前日: 前日1日間のデータを参照
--     - 過去3日: 前日から3日間のデータを参照
--     - 過去5日: 前日から5日間のデータを参照
--     - 過去7日: 前日から7日間のデータを参照
--     - 過去28日: 前日から28日間のデータを参照
--   複合戦略（長期×短期の組み合わせ）:
--     - 長期条件（28日間）と短期条件（3/5/7日間）を組み合わせた複合戦略
--
-- 【基本戦略（単一期間参照）】
--   各参照期間ごとに単一条件で評価する戦略
--   1. 差枚ベース（4種類）:
--      - 差枚ベスト1~5: 差枚1~5位の台を選ぶ
--      - 差枚ベスト6~10: 差枚6~10位の台を選ぶ
--      - 差枚ワースト1~5: 差枚下位1~5位の台を選ぶ
--      - 差枚ワースト6~10: 差枚下位6~10位の台を選ぶ
--   2. 勝率ベース（6段階、MECE）:
--      - 勝率100%: 全勝台を選ぶ
--      - 勝率75%超100%未満: 勝率75%超100%未満の台を選ぶ
--      - 勝率50%超75%以下: 勝率50%超75%以下の台を選ぶ
--      - 勝率25%超50%以下: 勝率25%超50%以下の台を選ぶ
--      - 勝率0%超25%未満: 勝率0%超25%未満の台を選ぶ
--      - 勝率0%: 全敗台を選ぶ
--   注意: 基本戦略には機械割ベースは含まれない
--         理由: 機械割は28日間の指標のため、基本戦略の「各参照期間ごとの単一条件」の
--               枠組みに収まらない。機械割は複合戦略の長期条件として使用される。
--
-- 【複合戦略（長期×短期の組み合わせ）】
--   長期条件（28日間）と短期条件（3/5/7日間）を組み合わせた戦略
--   1. 長期勝率ベース:
--      - 過去28日間勝率（4種類、MECE、パーセンタイルベース） × 短期条件（勝率条件または末尾関連性）
--   2. 長期機械割ベース:
--      - 過去28日間機械割（4種類、MECE） × 短期条件（勝率条件または末尾関連性）
--   3. 長期差枚ベース:
--      - 過去28日間差枚（4種類） × 短期条件（勝率条件または末尾関連性）
--
-- 【戦略の組み合わせロジック（複合戦略）】
--   長期条件（13種類）:
--     - 条件なし: 1種類
--     - 過去28日間勝率: 4種類（50.0%以上、42.9%以上50.0%未満、35.7%以上42.9%未満、35.7%未満、パーセンタイルベース）
--     - 過去28日間機械割: 4種類（104.47%以上、102.47%以上104.47%未満、100.91%以上102.47%未満、100.91%未満、パーセンタイルベース）
--     - 過去28日間差枚: 4種類（ベスト1~5、ベスト6~10、ワースト1~5、ワースト6~10）
--   短期条件（23種類）:
--     - 条件なし: 1種類
--     - 勝率条件: 18種類（6段階 × 3期間（3/5/7日間）、離散的で現在の区切りを維持）
--     - 末尾関連性: 4種類（末尾1桁=日付末尾1桁、末尾2桁=日付末尾2桁、末尾1桁=日付末尾1桁+1/-1）
--   短期条件は「勝率条件」と「末尾関連性」のいずれか1つのみ（両方は不可）
--   組み合わせ数: 13 × 23 = 299種類
--
-- 【MECE化の理由】
--   条件が重複すると、同じ台が複数の戦略に重複してカウントされ、評価が不当に高くなる
--   範囲を細かく分割することで、各条件が独立し、正確な評価が可能
--   長期条件の勝率は短期条件と同じ6段階に統一することで、評価ロジックを統一し、コードの重複を削減
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
--   基本戦略:
--     - 各参照期間（1/3/5/7/28日）ごとに単一条件で評価
--     - 差枚ベース（4種類）と勝率ベース（6段階）のみ
--     - 末尾関連性を適用しない（サンプルサイズ確保のため）
--     - 機械割ベースは含まれない（28日間の指標のため、基本戦略の枠組みに収まらない）
--   複合戦略:
--     - 長期条件（28日間）と短期条件（3/5/7日間）を組み合わせて評価
--     - 長期条件: 条件なし、勝率（6段階）、機械割（4種類）、差枚（4種類）
--     - 短期条件: 条件なし、勝率条件（18種類）、末尾関連性（4種類）
--     - 末尾関連性を含む全組み合わせを分析
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
    MOD(bd.machine_number, 100) AS machine_last_2digits,
    -- 過去28日間の差枚ランキング（複合戦略用）
    ROW_NUMBER() OVER (PARTITION BY bd.target_date ORDER BY bd.prev_d28_diff DESC) AS prev_d28_rank_best,
    ROW_NUMBER() OVER (PARTITION BY bd.target_date ORDER BY bd.prev_d28_diff ASC) AS prev_d28_rank_worst
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
      CAST(NULL AS STRING) AS lt_rank_type,
      CAST(NULL AS STRING) AS lt_rank_range,
      0 AS lt_sort
    ),
    -- 過去28日間勝率（4種類、MECE、パーセンタイルベース）
    STRUCT(
      '過去28日間勝率50.0%以上' AS lt_name,  -- 上位25%（p75以上）
      'win_rate' AS lt_type,
      0.50 AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      '>=' AS lt_op,
      CAST(NULL AS STRING) AS lt_rank_type,
      CAST(NULL AS STRING) AS lt_rank_range,
      1 AS lt_sort
    ),
    STRUCT(
      '過去28日間勝率42.9%以上50.0%未満' AS lt_name,  -- 上位25%〜50%（p50〜p75）
      'win_rate' AS lt_type,
      0.429 AS lt_threshold,
      0.50 AS lt_threshold_upper,
      '>=' AS lt_op,
      CAST(NULL AS STRING) AS lt_rank_type,
      CAST(NULL AS STRING) AS lt_rank_range,
      2 AS lt_sort
    ),
    STRUCT(
      '過去28日間勝率35.7%以上42.9%未満' AS lt_name,  -- 下位25%〜50%（p25〜p50）
      'win_rate' AS lt_type,
      0.357 AS lt_threshold,
      0.429 AS lt_threshold_upper,
      '>=' AS lt_op,
      CAST(NULL AS STRING) AS lt_rank_type,
      CAST(NULL AS STRING) AS lt_rank_range,
      3 AS lt_sort
    ),
    STRUCT(
      '過去28日間勝率35.7%未満' AS lt_name,  -- 下位25%（p25未満）
      'win_rate' AS lt_type,
      0.357 AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      '<' AS lt_op,
      CAST(NULL AS STRING) AS lt_rank_type,
      CAST(NULL AS STRING) AS lt_rank_range,
      4 AS lt_sort
    ),
    -- 過去28日間機械割（4種類、MECE、パーセンタイルベース）
    STRUCT(
      '過去28日間機械割104.47%以上' AS lt_name,  -- 上位25%（p75以上）
      'payout_rate' AS lt_type,
      1.0447 AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      '>=' AS lt_op,
      CAST(NULL AS STRING) AS lt_rank_type,
      CAST(NULL AS STRING) AS lt_rank_range,
      7 AS lt_sort
    ),
    STRUCT(
      '過去28日間機械割102.47%以上104.47%未満' AS lt_name,  -- 上位25%〜50%（p50〜p75）
      'payout_rate' AS lt_type,
      1.0247 AS lt_threshold,
      1.0447 AS lt_threshold_upper,
      '>=' AS lt_op,
      CAST(NULL AS STRING) AS lt_rank_type,
      CAST(NULL AS STRING) AS lt_rank_range,
      8 AS lt_sort
    ),
    STRUCT(
      '過去28日間機械割100.91%以上102.47%未満' AS lt_name,  -- 下位25%〜50%（p25〜p50）
      'payout_rate' AS lt_type,
      1.0091 AS lt_threshold,
      1.0247 AS lt_threshold_upper,
      '>=' AS lt_op,
      CAST(NULL AS STRING) AS lt_rank_type,
      CAST(NULL AS STRING) AS lt_rank_range,
      9 AS lt_sort
    ),
    STRUCT(
      '過去28日間機械割100.91%未満' AS lt_name,  -- 下位25%（p25未満）
      'payout_rate' AS lt_type,
      1.0091 AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      '<' AS lt_op,
      CAST(NULL AS STRING) AS lt_rank_type,
      CAST(NULL AS STRING) AS lt_rank_range,
      10 AS lt_sort
    ),
    -- 過去28日間差枚（4種類）
    STRUCT(
      '過去28日間差枚ベスト1~5' AS lt_name,
      'diff_rank' AS lt_type,
      CAST(NULL AS FLOAT64) AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      CAST(NULL AS STRING) AS lt_op,
      'best' AS lt_rank_type,
      '1-5' AS lt_rank_range,
      11 AS lt_sort
    ),
    STRUCT(
      '過去28日間差枚ベスト6~10' AS lt_name,
      'diff_rank' AS lt_type,
      CAST(NULL AS FLOAT64) AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      CAST(NULL AS STRING) AS lt_op,
      'best' AS lt_rank_type,
      '6-10' AS lt_rank_range,
      12 AS lt_sort
    ),
    STRUCT(
      '過去28日間差枚ワースト1~5' AS lt_name,
      'diff_rank' AS lt_type,
      CAST(NULL AS FLOAT64) AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      CAST(NULL AS STRING) AS lt_op,
      'worst' AS lt_rank_type,
      '1-5' AS lt_rank_range,
      13 AS lt_sort
    ),
    STRUCT(
      '過去28日間差枚ワースト6~10' AS lt_name,
      'diff_rank' AS lt_type,
      CAST(NULL AS FLOAT64) AS lt_threshold,
      CAST(NULL AS FLOAT64) AS lt_threshold_upper,
      CAST(NULL AS STRING) AS lt_op,
      'worst' AS lt_rank_type,
      '6-10' AS lt_rank_range,
      14 AS lt_sort
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
    lt.lt_rank_type, lt.lt_rank_range,
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
    STRUCT('差枚ベスト1~5' AS `戦略`, 1 AS strategy_order, p.rank_best BETWEEN 1 AND 5 AS matches),
    STRUCT('差枚ベスト6~10', 2, p.rank_best BETWEEN 6 AND 10),
    STRUCT('差枚ワースト1~5', 3, p.rank_worst BETWEEN 1 AND 5),
    STRUCT('差枚ワースト6~10', 4, p.rank_worst BETWEEN 6 AND 10),
    STRUCT('勝率100%', 5, p.ref_win_rate IS NOT NULL AND p.ref_win_rate = 1.0),
    STRUCT('勝率75%超100%未満', 6, p.ref_win_rate IS NOT NULL AND p.ref_win_rate > 0.75 AND p.ref_win_rate < 1.0),
    STRUCT('勝率50%超75%以下', 7, p.ref_win_rate IS NOT NULL AND p.ref_win_rate > 0.5 AND p.ref_win_rate <= 0.75),
    STRUCT('勝率25%超50%以下', 8, p.ref_win_rate IS NOT NULL AND p.ref_win_rate > 0.25 AND p.ref_win_rate <= 0.5),
    STRUCT('勝率0%超25%未満', 9, p.ref_win_rate IS NOT NULL AND p.ref_win_rate > 0.0 AND p.ref_win_rate < 0.25),
    STRUCT('勝率0%', 10, p.ref_win_rate IS NOT NULL AND p.ref_win_rate = 0.0)
  ]) AS s
  WHERE s.matches = TRUE
),

-- ----------------------------------------------------------------------------
-- 2-3. 複合戦略の動的条件評価
-- ----------------------------------------------------------------------------
-- prev_d* カラムを使用（当日を含まない）
-- ----------------------------------------------------------------------------
-- 複合戦略評価用: 期間別勝率値の計算（リファクタリング）
compound_evaluation_base AS (
  SELECT
    b.*,
    sc.*,
    -- 短期条件の期間別勝率値
    CASE sc.st_period
      WHEN 3 THEN b.prev_d3_win_rate
      WHEN 5 THEN b.prev_d5_win_rate
      WHEN 7 THEN b.prev_d7_win_rate
      ELSE NULL
    END AS st_win_rate_value
  FROM base_data_with_special b
  CROSS JOIN strategy_combinations sc
),

compound_with_strategies AS (
  SELECT 
    '複合' AS `参照期間`, 
    99 AS period_order,
    ceb.target_date, ceb.d1_diff, ceb.d1_game, ceb.is_holiday, ceb.is_special_day,
    ceb.strategy_name AS `戦略`, 
    ceb.sort_order AS strategy_order
  FROM compound_evaluation_base ceb
  WHERE 
    -- 長期条件の評価
    (
      ceb.lt_type = 'none'
      OR
      -- 勝率条件（短期と同じロジック、threshold_upperを使用）
      (ceb.lt_type = 'win_rate' AND ceb.prev_d28_win_rate IS NOT NULL AND (
        (ceb.lt_threshold_upper IS NULL AND (
          (ceb.lt_op = '>=' AND ceb.prev_d28_win_rate >= ceb.lt_threshold) OR
          (ceb.lt_op = '<=' AND ceb.prev_d28_win_rate <= ceb.lt_threshold) OR
          (ceb.lt_op = '>' AND ceb.prev_d28_win_rate > ceb.lt_threshold)
        ))
        OR
        (ceb.lt_threshold_upper IS NOT NULL AND (
          (ceb.lt_op = '>=' AND ceb.prev_d28_win_rate >= ceb.lt_threshold AND ceb.prev_d28_win_rate <= ceb.lt_threshold_upper) OR
          (ceb.lt_op = '>' AND ceb.prev_d28_win_rate > ceb.lt_threshold AND ceb.prev_d28_win_rate <= ceb.lt_threshold_upper)
        ))
      ))
      OR
      -- 機械割条件（既存のまま）
      (ceb.lt_type = 'payout_rate' AND (
        (ceb.lt_threshold_upper IS NULL AND (
          (ceb.lt_op = '>=' AND ceb.prev_d28_payout_rate >= ceb.lt_threshold) OR
          (ceb.lt_op = '<' AND ceb.prev_d28_payout_rate < ceb.lt_threshold)
        ))
        OR
        (ceb.lt_threshold_upper IS NOT NULL AND 
         ceb.prev_d28_payout_rate >= ceb.lt_threshold AND 
         ceb.prev_d28_payout_rate < ceb.lt_threshold_upper)
      ))
      OR
      -- 差枚条件（新規追加）
      (ceb.lt_type = 'diff_rank' AND (
        (ceb.lt_rank_type = 'best' AND (
          (ceb.lt_rank_range = '1-5' AND ceb.prev_d28_rank_best BETWEEN 1 AND 5) OR
          (ceb.lt_rank_range = '6-10' AND ceb.prev_d28_rank_best BETWEEN 6 AND 10)
        ))
        OR
        (ceb.lt_rank_type = 'worst' AND (
          (ceb.lt_rank_range = '1-5' AND ceb.prev_d28_rank_worst BETWEEN 1 AND 5) OR
          (ceb.lt_rank_range = '6-10' AND ceb.prev_d28_rank_worst BETWEEN 6 AND 10)
        ))
      ))
    )
    AND
    -- 短期条件の評価
    (
      ceb.st_type = 'none'
      OR
      -- 勝率条件（期間別勝率値を使用、統一されたロジックで評価）
      (ceb.st_type = 'win_rate' AND ceb.st_win_rate_value IS NOT NULL AND (
        (ceb.st_threshold_upper IS NULL AND (
          (ceb.st_op = '>=' AND ceb.st_win_rate_value >= ceb.st_threshold) OR
          (ceb.st_op = '<=' AND ceb.st_win_rate_value <= ceb.st_threshold) OR
          (ceb.st_op = '>' AND ceb.st_win_rate_value > ceb.st_threshold)
        ))
        OR
        (ceb.st_threshold_upper IS NOT NULL AND (
          (ceb.st_op = '>=' AND ceb.st_win_rate_value >= ceb.st_threshold AND ceb.st_win_rate_value <= ceb.st_threshold_upper) OR
          (ceb.st_op = '>' AND ceb.st_win_rate_value > ceb.st_threshold AND ceb.st_win_rate_value <= ceb.st_threshold_upper)
        ))
      ))
      OR
      -- 末尾関連性条件
      (ceb.st_type = 'digit_match_1' AND ceb.machine_last_1digit = ceb.date_last_1digit)
      OR
      (ceb.st_type = 'digit_match_2' AND ceb.machine_last_2digits = ceb.date_last_2digits)
      OR
      (ceb.st_type = 'digit_plus_1' AND ceb.machine_last_1digit = MOD(ceb.date_last_1digit + 1, 10))
      OR
      (ceb.st_type = 'digit_minus_1' AND ceb.machine_last_1digit = MOD(ceb.date_last_1digit - 1 + 10, 10))
    )
    AND (ceb.lt_type = 'none' OR ceb.lt_type = 'diff_rank' OR ceb.prev_d28_win_rate IS NOT NULL OR ceb.prev_d28_payout_rate IS NOT NULL)
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
  SELECT 
    b.*,
    -- 過去28日間の差枚ランキング（次の日の台番算出用、最新日を含む過去28日間の差枚でランキング）
    ROW_NUMBER() OVER (ORDER BY b.curr_d28_diff DESC) AS curr_d28_rank_best,
    ROW_NUMBER() OVER (ORDER BY b.curr_d28_diff ASC) AS curr_d28_rank_worst
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
    STRUCT('差枚ベスト1~5' AS `戦略`, 1 AS strategy_order, p.rank_best BETWEEN 1 AND 5 AS matches),
    STRUCT('差枚ベスト6~10', 2, p.rank_best BETWEEN 6 AND 10),
    STRUCT('差枚ワースト1~5', 3, p.rank_worst BETWEEN 1 AND 5),
    STRUCT('差枚ワースト6~10', 4, p.rank_worst BETWEEN 6 AND 10),
    STRUCT('勝率100%', 5, p.ref_win_rate IS NOT NULL AND p.ref_win_rate = 1.0),
    STRUCT('勝率75%超100%未満', 6, p.ref_win_rate IS NOT NULL AND p.ref_win_rate > 0.75 AND p.ref_win_rate < 1.0),
    STRUCT('勝率50%超75%以下', 7, p.ref_win_rate IS NOT NULL AND p.ref_win_rate > 0.5 AND p.ref_win_rate <= 0.75),
    STRUCT('勝率25%超50%以下', 8, p.ref_win_rate IS NOT NULL AND p.ref_win_rate > 0.25 AND p.ref_win_rate <= 0.5),
    STRUCT('勝率0%超25%未満', 9, p.ref_win_rate IS NOT NULL AND p.ref_win_rate > 0.0 AND p.ref_win_rate < 0.25),
    STRUCT('勝率0%', 10, p.ref_win_rate IS NOT NULL AND p.ref_win_rate = 0.0)
  ]) AS s
  WHERE s.matches = TRUE
  GROUP BY p.`参照期間`, p.period_order, s.`戦略`, s.strategy_order
),

-- 複合戦略評価用（次の日の台番算出）: 期間別勝率値の計算（リファクタリング）
next_compound_evaluation_base AS (
  SELECT
    ld.*,
    sc.*,
    ndi.*,
    -- 短期条件の期間別勝率値
    CASE sc.st_period
      WHEN 3 THEN ld.curr_d3_win_rate
      WHEN 5 THEN ld.curr_d5_win_rate
      WHEN 7 THEN ld.curr_d7_win_rate
      ELSE NULL
    END AS st_win_rate_value
  FROM latest_data ld
  CROSS JOIN strategy_combinations sc
  CROSS JOIN next_day_info ndi
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
    ceb.strategy_name AS `戦略`,
    ceb.sort_order AS strategy_order,
    STRING_AGG(CAST(ceb.machine_number AS STRING), ', ' ORDER BY ceb.machine_number) AS target_machines
  FROM next_compound_evaluation_base ceb
  WHERE 
    -- 長期条件の評価（curr_d28_* を使用）
    (
      ceb.lt_type = 'none'
      OR
      -- 勝率条件（短期と同じロジック、threshold_upperを使用）
      (ceb.lt_type = 'win_rate' AND ceb.curr_d28_win_rate IS NOT NULL AND (
        (ceb.lt_threshold_upper IS NULL AND (
          (ceb.lt_op = '>=' AND ceb.curr_d28_win_rate >= ceb.lt_threshold) OR
          (ceb.lt_op = '<=' AND ceb.curr_d28_win_rate <= ceb.lt_threshold) OR
          (ceb.lt_op = '>' AND ceb.curr_d28_win_rate > ceb.lt_threshold)
        ))
        OR
        (ceb.lt_threshold_upper IS NOT NULL AND (
          (ceb.lt_op = '>=' AND ceb.curr_d28_win_rate >= ceb.lt_threshold AND ceb.curr_d28_win_rate <= ceb.lt_threshold_upper) OR
          (ceb.lt_op = '>' AND ceb.curr_d28_win_rate > ceb.lt_threshold AND ceb.curr_d28_win_rate <= ceb.lt_threshold_upper)
        ))
      ))
      OR
      -- 機械割条件（既存のまま）
      (ceb.lt_type = 'payout_rate' AND (
        (ceb.lt_threshold_upper IS NULL AND (
          (ceb.lt_op = '>=' AND ceb.curr_d28_payout_rate >= ceb.lt_threshold) OR
          (ceb.lt_op = '<' AND ceb.curr_d28_payout_rate < ceb.lt_threshold)
        ))
        OR
        (ceb.lt_threshold_upper IS NOT NULL AND 
         ceb.curr_d28_payout_rate >= ceb.lt_threshold AND 
         ceb.curr_d28_payout_rate < ceb.lt_threshold_upper)
      ))
      OR
      -- 差枚条件（新規追加）
      (ceb.lt_type = 'diff_rank' AND (
        (ceb.lt_rank_type = 'best' AND (
          (ceb.lt_rank_range = '1-5' AND ceb.curr_d28_rank_best BETWEEN 1 AND 5) OR
          (ceb.lt_rank_range = '6-10' AND ceb.curr_d28_rank_best BETWEEN 6 AND 10)
        ))
        OR
        (ceb.lt_rank_type = 'worst' AND (
          (ceb.lt_rank_range = '1-5' AND ceb.curr_d28_rank_worst BETWEEN 1 AND 5) OR
          (ceb.lt_rank_range = '6-10' AND ceb.curr_d28_rank_worst BETWEEN 6 AND 10)
        ))
      ))
    )
    AND
    -- 短期条件の評価（curr_d3/5/7_* を使用、末尾関連性はnext_dateを使用）
    (
      ceb.st_type = 'none'
      OR
      -- 勝率条件（期間別勝率値を使用、統一されたロジックで評価）
      (ceb.st_type = 'win_rate' AND ceb.st_win_rate_value IS NOT NULL AND (
        (ceb.st_threshold_upper IS NULL AND (
          (ceb.st_op = '>=' AND ceb.st_win_rate_value >= ceb.st_threshold) OR
          (ceb.st_op = '<=' AND ceb.st_win_rate_value <= ceb.st_threshold) OR
          (ceb.st_op = '>' AND ceb.st_win_rate_value > ceb.st_threshold)
        ))
        OR
        (ceb.st_threshold_upper IS NOT NULL AND (
          (ceb.st_op = '>=' AND ceb.st_win_rate_value >= ceb.st_threshold AND ceb.st_win_rate_value <= ceb.st_threshold_upper) OR
          (ceb.st_op = '>' AND ceb.st_win_rate_value > ceb.st_threshold AND ceb.st_win_rate_value <= ceb.st_threshold_upper)
        ))
      ))
      OR
      -- 末尾関連性条件
      (ceb.st_type = 'digit_match_1' AND ceb.machine_last_1digit = ceb.next_date_last_1digit)
      OR
      (ceb.st_type = 'digit_match_2' AND ceb.machine_last_2digits = ceb.next_date_last_2digits)
      OR
      (ceb.st_type = 'digit_plus_1' AND ceb.machine_last_1digit = MOD(ceb.next_date_last_1digit + 1, 10))
      OR
      (ceb.st_type = 'digit_minus_1' AND ceb.machine_last_1digit = MOD(ceb.next_date_last_1digit - 1 + 10, 10))
    )
    AND (ceb.lt_type = 'none' OR ceb.lt_type = 'diff_rank' OR ceb.curr_d28_win_rate IS NOT NULL OR ceb.curr_d28_payout_rate IS NOT NULL)
  GROUP BY ceb.strategy_name, ceb.sort_order
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

