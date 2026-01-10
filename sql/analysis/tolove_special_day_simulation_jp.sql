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
--   過去N日間のデータを参照して台を選ぶ
--   - 前日: 前日1日間
--   - 過去3日: 前日から3日間
--   - 過去5日: 前日から5日間
--   - 過去7日: 前日から7日間
--   - 過去28日: 前日から28日間
--
-- 【戦略（差枚ベース）】
--   - 差枚ベスト1: 差枚1位の台を選ぶ
--   - 差枚ベスト3: 差枚上位3台を選ぶ
--   - 差枚ワースト1: 差枚最下位の台を選ぶ
--   - 差枚ワースト3: 差枚下位3台を選ぶ
--
-- 【戦略（勝率ベース）】※参照期間3日以上のみ
--   - 勝率100%: 全勝台を選ぶ
--   - 勝率60%以上: 勝率60%以上の台を選ぶ
--   - 勝率30%以下: 勝率30%以下の台を選ぶ
--   - 勝率0%: 全敗台を選ぶ
--
-- 【出力項目】
--   - 曜日: 曜日カテゴリ
--   - 参照期間: 何日前のデータを参照したか
--   - 戦略: 台選び戦略
--   - 実施日数: 戦略を実施できた日数
--   - 参照台数: 戦略に該当した台の延べ数
--   - 勝利日数: プラス収支だった回数
--   - 勝率: 勝利日数 / 参照台数 * 100
--   - 合計差枚: 差枚の合計
--   - 平均差枚: 差枚の平均
--   - 機械割: (合計ゲーム数*3 + 合計差枚) / (合計ゲーム数*3) * 100
--
-- 【拡張方法】
--   - 曜日カテゴリ追加: day_categories CTEに行を追加
--   - 参照期間追加: periods CTEにUNION ALLで追加
--   - 戦略追加: strategies CTEのUNNEST配列に要素を追加
-- ============================================================================

WITH 
-- ============================================================================
-- 1. 基本データ（各種フラグ付き）
-- ============================================================================
base_data AS (
  SELECT
    target_date,
    machine_number,
    d1_diff,
    d1_game,
    prev_d1_diff,
    prev_d3_diff,
    prev_d5_diff,
    prev_d7_diff,
    prev_d28_diff,
    prev_d3_win_rate,
    prev_d5_win_rate,
    prev_d7_win_rate,
    prev_d28_win_rate,
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

-- ============================================================================
-- 2. 参照期間ごとのデータ（縦持ち変換 + ランキング計算）
-- ============================================================================
periods_data AS (
  -- 前日
  SELECT 
    '前日' AS `参照期間`,
    1 AS period_order,
    target_date, machine_number, d1_diff, d1_game,
    prev_d1_diff AS ref_diff,
    CAST(NULL AS FLOAT64) AS ref_win_rate,
    is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d1_diff DESC) AS rank_best,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d1_diff ASC) AS rank_worst
  FROM base_data 
  WHERE prev_d1_diff IS NOT NULL

  UNION ALL

  -- 過去3日
  SELECT 
    '過去3日', 2,
    target_date, machine_number, d1_diff, d1_game,
    prev_d3_diff, prev_d3_win_rate,
    is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d3_diff DESC),
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d3_diff ASC)
  FROM base_data 
  WHERE prev_d3_diff IS NOT NULL

  UNION ALL

  -- 過去5日
  SELECT 
    '過去5日', 3,
    target_date, machine_number, d1_diff, d1_game,
    prev_d5_diff, prev_d5_win_rate,
    is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d5_diff DESC),
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d5_diff ASC)
  FROM base_data 
  WHERE prev_d5_diff IS NOT NULL

  UNION ALL

  -- 過去7日
  SELECT 
    '過去7日', 4,
    target_date, machine_number, d1_diff, d1_game,
    prev_d7_diff, prev_d7_win_rate,
    is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d7_diff DESC),
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d7_diff ASC)
  FROM base_data 
  WHERE prev_d7_diff IS NOT NULL

  UNION ALL

  -- 過去28日
  SELECT 
    '過去28日', 5,
    target_date, machine_number, d1_diff, d1_game,
    prev_d28_diff, prev_d28_win_rate,
    is_holiday, is_special_day,
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d28_diff DESC),
    ROW_NUMBER() OVER (PARTITION BY target_date ORDER BY prev_d28_diff ASC)
  FROM base_data 
  WHERE prev_d28_diff IS NOT NULL
),

-- ============================================================================
-- 3. 曜日カテゴリ定義
-- ============================================================================
day_categories AS (
  SELECT '全日' AS `曜日`, 1 AS day_order, 'all' AS day_filter UNION ALL
  SELECT '平日', 2, 'weekday' UNION ALL
  SELECT '土日祝', 3, 'holiday' UNION ALL
  SELECT '特日', 4, 'special'
),

-- ============================================================================
-- 4. 戦略適用（各レコードに該当する戦略を付与）
-- ============================================================================
with_strategies AS (
  SELECT 
    p.*,
    s.`戦略`,
    s.strategy_order
  FROM periods_data p
  CROSS JOIN UNNEST([
    -- 差枚ベース戦略
    STRUCT('差枚ベスト1' AS `戦略`, 1 AS strategy_order, p.rank_best = 1 AS matches),
    STRUCT('差枚ベスト3', 2, p.rank_best <= 3),
    STRUCT('差枚ワースト1', 3, p.rank_worst = 1),
    STRUCT('差枚ワースト3', 4, p.rank_worst <= 3),
    -- 勝率ベース戦略（前日は勝率データなしのためNULLチェック）
    STRUCT('勝率100%', 5, p.ref_win_rate IS NOT NULL AND p.ref_win_rate = 1.0),
    STRUCT('勝率60%以上', 6, p.ref_win_rate IS NOT NULL AND p.ref_win_rate >= 0.6),
    STRUCT('勝率30%以下', 7, p.ref_win_rate IS NOT NULL AND p.ref_win_rate <= 0.3),
    STRUCT('勝率0%', 8, p.ref_win_rate IS NOT NULL AND p.ref_win_rate = 0)
  ]) AS s
  WHERE s.matches = TRUE
),

-- ============================================================================
-- 5. 曜日カテゴリ × 戦略データの結合
-- ============================================================================
categorized_data AS (
  SELECT 
    dc.`曜日`,
    dc.day_order,
    ws.`参照期間`,
    ws.period_order,
    ws.`戦略`,
    ws.strategy_order,
    ws.target_date,
    ws.d1_diff,
    ws.d1_game
  FROM with_strategies ws
  CROSS JOIN day_categories dc
  WHERE 
    (dc.day_filter = 'all') OR
    (dc.day_filter = 'weekday' AND ws.is_holiday = FALSE) OR
    (dc.day_filter = 'holiday' AND ws.is_holiday = TRUE) OR
    (dc.day_filter = 'special' AND ws.is_special_day = TRUE)
)

-- ============================================================================
-- 6. 最終集計
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
