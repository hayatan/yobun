-- ============================================================================
-- 日付カテゴリ別効果検証
-- ============================================================================
--
-- 【概要】
--   LINE告知 / 特日 / 通常日 それぞれの機械割・勝率を比較し、
--   各カテゴリの効果を検証する。
--
-- 【日付カテゴリ】（優先順位順）
--   1. LINE告知: eventsテーブルから取得（最優先）
--   2. 月末: 月末日（LINE告知日は除外）
--   3. 0のつく日: 10, 20, 30日
--   4. 1のつく日: 1, 11, 21, 31日
--   5. 6のつく日: 6, 16, 26日
--   6. 8のつく日: 8, 18, 28日
--   7. 9のつく日: 9, 19, 29日
--   8. 通常日: 上記以外
--
-- 【出力】
--   カテゴリ別サマリー: 各カテゴリの平均機械割・勝率
--
-- 【使い方】
--   BigQueryコンソールで実行
--   パラメータを変更する場合は DECLARE 文を編集
--
-- ============================================================================

-- パラメータ定義
DECLARE target_hole STRING DEFAULT 'アイランド秋葉原店';
DECLARE target_machine STRING DEFAULT 'L+ToLOVEるダークネス';
DECLARE eval_start_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 360 DAY);
DECLARE eval_end_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);

-- ============================================================================
-- メインクエリ
-- ============================================================================

WITH
-- ----------------------------------------------------------------------------
-- 1. 対象データの取得
-- ----------------------------------------------------------------------------
base_data AS (
  SELECT
    ms.target_date,
    ms.hole,
    ms.machine,
    ms.machine_number,
    ms.d1_diff,
    ms.d1_game,
    ms.d1_payout_rate,
    -- 勝敗判定（差枚 > 0 なら勝ち）
    CASE WHEN ms.d1_diff > 0 THEN 1 ELSE 0 END AS win
  FROM `yobun-450512.datamart.machine_stats` ms
  WHERE ms.hole = target_hole
    AND ms.machine = target_machine
    AND ms.target_date BETWEEN eval_start_date AND eval_end_date
    AND ms.d1_game IS NOT NULL
    AND ms.d1_game > 0
),

-- ----------------------------------------------------------------------------
-- 2. イベント情報の取得（LINE告知など）
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
-- 3. 日付カテゴリの判定
-- ----------------------------------------------------------------------------
categorized_data AS (
  SELECT
    bd.*,
    ed.event AS event_type,
    EXTRACT(DAY FROM bd.target_date) AS day_of_month,
    MOD(EXTRACT(DAY FROM bd.target_date), 10) AS day_last_digit,
    -- カテゴリ分類（優先順位: LINE告知 > 月末 > 末尾日 > 通常日）
    CASE
      WHEN ed.event IS NOT NULL THEN 'LINE告知'
      WHEN bd.target_date = LAST_DAY(bd.target_date) THEN '月末'
      WHEN MOD(EXTRACT(DAY FROM bd.target_date), 10) = 0 THEN '0のつく日'
      WHEN MOD(EXTRACT(DAY FROM bd.target_date), 10) = 1 THEN '1のつく日'
      WHEN MOD(EXTRACT(DAY FROM bd.target_date), 10) = 6 THEN '6のつく日'
      WHEN MOD(EXTRACT(DAY FROM bd.target_date), 10) = 8 THEN '8のつく日'
      WHEN MOD(EXTRACT(DAY FROM bd.target_date), 10) = 9 THEN '9のつく日'
      ELSE '通常日'
    END AS day_category
  FROM base_data bd
  LEFT JOIN events_data ed
    ON bd.target_date = ed.event_date
    AND bd.hole = ed.hole
),

-- ----------------------------------------------------------------------------
-- 4. 全体平均のベースライン計算
-- ----------------------------------------------------------------------------
baseline AS (
  SELECT
    AVG(d1_payout_rate) AS baseline_payout_rate,
    AVG(win) AS baseline_win_rate
  FROM categorized_data
),

-- ----------------------------------------------------------------------------
-- 5. カテゴリ別サマリー
-- ----------------------------------------------------------------------------
category_summary AS (
  SELECT
    cd.day_category,
    COUNT(DISTINCT cd.target_date) AS sample_days,
    COUNT(*) AS sample_records,
    AVG(cd.d1_diff) AS avg_diff,
    SUM(cd.d1_game) AS total_game,
    AVG(cd.d1_payout_rate) AS avg_payout_rate,
    AVG(cd.win) AS avg_win_rate,
    STDDEV(cd.d1_payout_rate) AS stddev_payout_rate,
    -- ベースラインとの差
    AVG(cd.d1_payout_rate) - b.baseline_payout_rate AS vs_baseline_payout,
    AVG(cd.win) - b.baseline_win_rate AS vs_baseline_win
  FROM categorized_data cd
  CROSS JOIN baseline b
  GROUP BY cd.day_category, b.baseline_payout_rate, b.baseline_win_rate
)

-- ============================================================================
-- 出力: カテゴリ別サマリー
-- ============================================================================
SELECT
  day_category,
  sample_days,
  sample_records,
  ROUND(avg_diff, 0) AS avg_diff,
  total_game,
  ROUND(avg_payout_rate, 4) AS avg_payout_rate,
  ROUND(avg_win_rate, 4) AS avg_win_rate,
  ROUND(stddev_payout_rate, 4) AS stddev_payout_rate,
  ROUND(vs_baseline_payout, 4) AS vs_baseline_payout,
  ROUND(vs_baseline_win, 4) AS vs_baseline_win,
  -- カテゴリ順序（表示用）
  CASE day_category
    WHEN 'LINE告知' THEN 1
    WHEN '月末' THEN 2
    WHEN '0のつく日' THEN 3
    WHEN '1のつく日' THEN 4
    WHEN '6のつく日' THEN 5
    WHEN '8のつく日' THEN 6
    WHEN '9のつく日' THEN 7
    WHEN '通常日' THEN 8
  END AS sort_order
FROM category_summary
ORDER BY sort_order;
