-- ============================================================================
-- 狙い台出力クエリ（シンプル版）
-- ============================================================================
--
-- 【概要】
--   検証結果に基づき、有効な戦略に合致する台を優先度ランク付きで出力する。
--
-- 【優先度ランク】
--   5: Tier S - 出率108%超え（8のつく日+連敗、LINE告知+5連敗）
--   4: Tier A - 出率106-108%（月末+3連敗、通常日+5連勝、LINE告知+3連勝、月末+2連敗）
--   3: Tier B - 出率106%前後（LINE告知+3連敗、5連勝）
--   2: Tier C - 日付カテゴリのみ（LINE告知、月末）
--   1: Tier D - 連勝/連敗条件のみ（3連勝、3連敗）
--   0: 対象外（0のつく日、1のつく日を含む）
--
-- 【使い方】
--   BigQueryコンソールで実行
--   target_dateをNULLにするとdatamartの最新データ日の翌日を自動計算
--
-- ============================================================================

-- パラメータ定義
DECLARE target_hole STRING DEFAULT 'アイランド秋葉原店';
DECLARE target_machine STRING DEFAULT 'L+ToLOVEるダークネス';
DECLARE target_date DATE DEFAULT NULL;  -- NULLの場合はdatamartの最新データ日の翌日を自動計算

-- ============================================================================
-- メインクエリ
-- ============================================================================

WITH
-- ----------------------------------------------------------------------------
-- 1. datamartの最新データ日を取得
-- ----------------------------------------------------------------------------
latest_datamart_date AS (
  SELECT MAX(target_date) AS max_date
  FROM `yobun-450512.datamart.machine_stats`
  WHERE hole = target_hole
    AND machine = target_machine
),

-- ----------------------------------------------------------------------------
-- 2. 対象日の決定（datamartの最新日の翌日）
-- ----------------------------------------------------------------------------
target_date_calc AS (
  SELECT
    COALESCE(target_date, DATE_ADD(ldd.max_date, INTERVAL 1 DAY)) AS calc_target_date,
    ldd.max_date AS data_latest_date
  FROM latest_datamart_date ldd
),

-- ----------------------------------------------------------------------------
-- 3. イベント情報の取得（LINE告知など）
-- ----------------------------------------------------------------------------
events_data AS (
  SELECT
    PARSE_DATE('%Y-%m-%d', date) AS event_date,
    hole,
    event
  FROM `yobun-450512.slot_data.events`
  WHERE hole = target_hole
),

-- ----------------------------------------------------------------------------
-- 4. 対象日の日付カテゴリ判定
-- ----------------------------------------------------------------------------
target_day_info AS (
  SELECT
    tdc.calc_target_date AS target_date,
    tdc.data_latest_date,
    ed.event AS event_type,
    -- 日付カテゴリ
    CASE
      WHEN ed.event IS NOT NULL THEN 'LINE告知'
      WHEN tdc.calc_target_date = LAST_DAY(tdc.calc_target_date) THEN '月末'
      WHEN MOD(EXTRACT(DAY FROM tdc.calc_target_date), 10) = 0 THEN '0のつく日'
      WHEN MOD(EXTRACT(DAY FROM tdc.calc_target_date), 10) = 1 THEN '1のつく日'
      WHEN MOD(EXTRACT(DAY FROM tdc.calc_target_date), 10) = 6 THEN '6のつく日'
      WHEN MOD(EXTRACT(DAY FROM tdc.calc_target_date), 10) = 8 THEN '8のつく日'
      WHEN MOD(EXTRACT(DAY FROM tdc.calc_target_date), 10) = 9 THEN '9のつく日'
      ELSE '通常日'
    END AS day_category
  FROM target_date_calc tdc
  LEFT JOIN events_data ed
    ON tdc.calc_target_date = ed.event_date
    AND ed.hole = target_hole
),

-- ----------------------------------------------------------------------------
-- 5. 前日時点の台データ取得（最新のデータ）
-- ----------------------------------------------------------------------------
latest_data AS (
  SELECT
    ms.machine_number,
    ms.machine,
    ms.target_date AS data_date,
    ms.prev_d2_win_rate,
    ms.prev_d3_win_rate,
    ms.prev_d5_win_rate,
    -- 連勝/連敗パターン分類
    CASE
      WHEN ms.prev_d2_win_rate = 1.0 THEN '2連勝'
      WHEN ms.prev_d2_win_rate = 0.0 THEN '2連敗'
      ELSE NULL
    END AS d2_pattern,
    CASE
      WHEN ms.prev_d3_win_rate = 1.0 THEN '3連勝'
      WHEN ms.prev_d3_win_rate = 0.0 THEN '3連敗'
      ELSE NULL
    END AS d3_pattern,
    CASE
      WHEN ms.prev_d5_win_rate = 1.0 THEN '5連勝'
      WHEN ms.prev_d5_win_rate = 0.0 THEN '5連敗'
      ELSE NULL
    END AS d5_pattern
  FROM `yobun-450512.datamart.machine_stats` ms
  CROSS JOIN latest_datamart_date ldd
  WHERE ms.hole = target_hole
    AND ms.machine = target_machine
    AND ms.target_date = ldd.max_date
),

-- ----------------------------------------------------------------------------
-- 6. 優先度ランク付け
-- ----------------------------------------------------------------------------
ranked_machines AS (
  SELECT
    tdi.target_date,
    tdi.data_latest_date,
    tdi.day_category,
    tdi.event_type,
    ld.machine_number,
    ld.machine,
    ld.prev_d2_win_rate,
    ld.prev_d3_win_rate,
    ld.prev_d5_win_rate,
    ld.d2_pattern,
    ld.d3_pattern,
    ld.d5_pattern,
    -- 優先度ランク計算（検証結果に基づく）
    CASE
      -- 対象外: 0のつく日、1のつく日は避ける
      WHEN tdi.day_category IN ('0のつく日', '1のつく日') THEN 0
      
      -- Tier S: 出率108%超え
      WHEN tdi.day_category = '8のつく日' AND ld.d3_pattern = '3連敗' THEN 5  -- 108.81%
      WHEN tdi.day_category = '8のつく日' AND ld.d5_pattern = '5連敗' THEN 5  -- 108.30%
      WHEN tdi.day_category = 'LINE告知' AND ld.d5_pattern = '5連敗' THEN 5   -- 108.15%
      
      -- Tier A: 出率106-108%
      WHEN tdi.day_category = '月末' AND ld.d3_pattern = '3連敗' THEN 4       -- 107.80%
      WHEN ld.d5_pattern = '5連勝' THEN 4                                     -- 107.24% (通常日でも有効)
      WHEN tdi.day_category = 'LINE告知' AND ld.d3_pattern = '3連勝' THEN 4   -- 106.82%
      WHEN tdi.day_category = '月末' AND ld.d2_pattern = '2連敗' THEN 4       -- 106.09%
      
      -- Tier B: 出率106%前後
      WHEN tdi.day_category = 'LINE告知' AND ld.d3_pattern = '3連敗' THEN 3   -- 106.01%
      WHEN tdi.day_category = 'LINE告知' AND ld.d2_pattern = '2連勝' THEN 3   -- 105.45%
      WHEN tdi.day_category = 'LINE告知' AND ld.d5_pattern = '5連勝' THEN 3   -- 105.31%
      
      -- Tier C: 日付カテゴリのみ
      WHEN tdi.day_category = 'LINE告知' THEN 2                               -- 103.99%
      WHEN tdi.day_category = '月末' THEN 2                                   -- 103.86%
      
      -- Tier D: 連勝/連敗条件のみ
      WHEN ld.d3_pattern = '3連勝' THEN 1                                     -- 103.53%
      WHEN ld.d3_pattern = '3連敗' THEN 1                                     -- 103.68%
      
      -- 対象外
      ELSE 0
    END AS priority_rank,
    -- 戦略名
    CASE
      WHEN tdi.day_category IN ('0のつく日', '1のつく日') THEN '対象外（避けるべき日）'
      WHEN tdi.day_category = '8のつく日' AND ld.d3_pattern = '3連敗' THEN '8のつく日+3連敗 (108.81%)'
      WHEN tdi.day_category = '8のつく日' AND ld.d5_pattern = '5連敗' THEN '8のつく日+5連敗 (108.30%)'
      WHEN tdi.day_category = 'LINE告知' AND ld.d5_pattern = '5連敗' THEN 'LINE告知+5連敗 (108.15%)'
      WHEN tdi.day_category = '月末' AND ld.d3_pattern = '3連敗' THEN '月末+3連敗 (107.80%)'
      WHEN ld.d5_pattern = '5連勝' THEN tdi.day_category || '+5連勝 (107.24%)'
      WHEN tdi.day_category = 'LINE告知' AND ld.d3_pattern = '3連勝' THEN 'LINE告知+3連勝 (106.82%)'
      WHEN tdi.day_category = '月末' AND ld.d2_pattern = '2連敗' THEN '月末+2連敗 (106.09%)'
      WHEN tdi.day_category = 'LINE告知' AND ld.d3_pattern = '3連敗' THEN 'LINE告知+3連敗 (106.01%)'
      WHEN tdi.day_category = 'LINE告知' AND ld.d2_pattern = '2連勝' THEN 'LINE告知+2連勝 (105.45%)'
      WHEN tdi.day_category = 'LINE告知' AND ld.d5_pattern = '5連勝' THEN 'LINE告知+5連勝 (105.31%)'
      WHEN tdi.day_category = 'LINE告知' THEN 'LINE告知のみ (103.99%)'
      WHEN tdi.day_category = '月末' THEN '月末のみ (103.86%)'
      WHEN ld.d3_pattern = '3連勝' THEN '3連勝のみ (103.53%)'
      WHEN ld.d3_pattern = '3連敗' THEN '3連敗のみ (103.68%)'
      ELSE '対象外'
    END AS strategy_name
  FROM target_day_info tdi
  CROSS JOIN latest_data ld
)

-- ============================================================================
-- 出力: 優先度ランク順に狙い台を表示
-- ============================================================================
SELECT
  target_date,
  data_latest_date,
  day_category,
  machine_number,
  priority_rank,
  strategy_name,
  ROUND(prev_d2_win_rate, 2) AS d2_win_rate,
  ROUND(prev_d3_win_rate, 2) AS d3_win_rate,
  ROUND(prev_d5_win_rate, 2) AS d5_win_rate,
  d2_pattern,
  d3_pattern,
  d5_pattern
FROM ranked_machines
WHERE priority_rank > 0
ORDER BY priority_rank DESC, machine_number;
