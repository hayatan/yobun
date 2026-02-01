-- データマートテーブル作成DDL
-- 実行場所: BigQueryコンソール
-- 実行タイミング: 初回のみ（スケジュールクエリ設定前）
-- 
-- 注意: テーブル構造を変更する場合は、既存テーブルを削除してから再作成
-- DROP TABLE IF EXISTS `yobun-450512.datamart.machine_stats`;

-- ============================================================================
-- datamart データセットの作成（存在しない場合）
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS `yobun-450512.datamart`
OPTIONS (
  location = 'US',
  description = 'データマート用データセット'
);

-- ============================================================================
-- machine_stats パーティションテーブルの作成
-- ============================================================================
CREATE TABLE IF NOT EXISTS `yobun-450512.datamart.machine_stats` (
  -- 基本情報
  target_date DATE NOT NULL OPTIONS(description = '集計日'),
  hole STRING NOT NULL OPTIONS(description = '店舗名'),
  machine_number INT64 NOT NULL OPTIONS(description = '台番'),
  machine STRING OPTIONS(description = '機種名'),
  
  -- 集計期間
  start_date DATE OPTIONS(description = '集計開始日（機種変更を考慮）'),
  end_date DATE OPTIONS(description = '集計終了日（=集計日）'),
  
  -- ========================================
  -- 日付関連カラム
  -- ========================================
  target_year INT64 OPTIONS(description = '年'),
  target_month INT64 OPTIONS(description = '月'),
  target_day INT64 OPTIONS(description = '日'),
  target_day_last_digit INT64 OPTIONS(description = '日の下1桁'),
  is_month_day_repdigit BOOL OPTIONS(description = '月と日がゾロ目か (01/01, 02/02, ..., 12/12)'),
  is_day_repdigit BOOL OPTIONS(description = '日がゾロ目か (11, 22)'),
  day_of_week_jp STRING OPTIONS(description = '曜日（日本語: 月,火,水,木,金,土,日）'),
  day_type STRING OPTIONS(description = '平日/週末/祝日'),
  
  -- ========================================
  -- 当日データ
  -- ========================================
  d1_diff INT64 OPTIONS(description = '当日 差枚'),
  d1_game INT64 OPTIONS(description = '当日 ゲーム数'),
  d1_payout_rate FLOAT64 OPTIONS(description = '当日 機械割'),
  
  -- ========================================
  -- 当日から過去N日間（当日を含む）
  -- ========================================
  -- 2日間（当日〜1日前）
  d2_diff INT64 OPTIONS(description = '当日から2日間 総差枚'),
  d2_game INT64 OPTIONS(description = '当日から2日間 総ゲーム数'),
  d2_win_rate FLOAT64 OPTIONS(description = '当日から2日間 勝率'),
  d2_payout_rate FLOAT64 OPTIONS(description = '当日から2日間 機械割'),
  
  -- 3日間（当日〜2日前）
  d3_diff INT64 OPTIONS(description = '当日から3日間 総差枚'),
  d3_game INT64 OPTIONS(description = '当日から3日間 総ゲーム数'),
  d3_win_rate FLOAT64 OPTIONS(description = '当日から3日間 勝率'),
  d3_payout_rate FLOAT64 OPTIONS(description = '当日から3日間 機械割'),
  
  -- 4日間（当日〜3日前）
  d4_diff INT64 OPTIONS(description = '当日から4日間 総差枚'),
  d4_game INT64 OPTIONS(description = '当日から4日間 総ゲーム数'),
  d4_win_rate FLOAT64 OPTIONS(description = '当日から4日間 勝率'),
  d4_payout_rate FLOAT64 OPTIONS(description = '当日から4日間 機械割'),
  
  -- 5日間（当日〜4日前）
  d5_diff INT64 OPTIONS(description = '当日から5日間 総差枚'),
  d5_game INT64 OPTIONS(description = '当日から5日間 総ゲーム数'),
  d5_win_rate FLOAT64 OPTIONS(description = '当日から5日間 勝率'),
  d5_payout_rate FLOAT64 OPTIONS(description = '当日から5日間 機械割'),
  
  -- 6日間（当日〜5日前）
  d6_diff INT64 OPTIONS(description = '当日から6日間 総差枚'),
  d6_game INT64 OPTIONS(description = '当日から6日間 総ゲーム数'),
  d6_win_rate FLOAT64 OPTIONS(description = '当日から6日間 勝率'),
  d6_payout_rate FLOAT64 OPTIONS(description = '当日から6日間 機械割'),
  
  -- 7日間（当日〜6日前）
  d7_diff INT64 OPTIONS(description = '当日から7日間 総差枚'),
  d7_game INT64 OPTIONS(description = '当日から7日間 総ゲーム数'),
  d7_win_rate FLOAT64 OPTIONS(description = '当日から7日間 勝率'),
  d7_payout_rate FLOAT64 OPTIONS(description = '当日から7日間 機械割'),
  
  -- 14日間（当日〜13日前）
  d14_diff INT64 OPTIONS(description = '当日から14日間 総差枚'),
  d14_game INT64 OPTIONS(description = '当日から14日間 総ゲーム数'),
  d14_win_rate FLOAT64 OPTIONS(description = '当日から14日間 勝率'),
  d14_payout_rate FLOAT64 OPTIONS(description = '当日から14日間 機械割'),
  
  -- 28日間（当日〜27日前）
  d28_diff INT64 OPTIONS(description = '当日から28日間 総差枚'),
  d28_game INT64 OPTIONS(description = '当日から28日間 総ゲーム数'),
  d28_win_rate FLOAT64 OPTIONS(description = '当日から28日間 勝率'),
  d28_payout_rate FLOAT64 OPTIONS(description = '当日から28日間 機械割'),
  
  -- 当月（当日〜月初）
  mtd_diff INT64 OPTIONS(description = '当日から当月 総差枚'),
  mtd_game INT64 OPTIONS(description = '当日から当月 総ゲーム数'),
  mtd_win_rate FLOAT64 OPTIONS(description = '当日から当月 勝率'),
  mtd_payout_rate FLOAT64 OPTIONS(description = '当日から当月 機械割'),
  
  -- 全期間（当日〜データ開始日）
  all_diff INT64 OPTIONS(description = '当日から全期間 総差枚'),
  all_game INT64 OPTIONS(description = '当日から全期間 総ゲーム数'),
  all_win_rate FLOAT64 OPTIONS(description = '当日から全期間 勝率'),
  all_payout_rate FLOAT64 OPTIONS(description = '当日から全期間 機械割'),
  all_days INT64 OPTIONS(description = '当日から全期間 集計日数'),
  
  -- ========================================
  -- 前日から過去N日間（当日を含まない）
  -- ========================================
  -- 前日のみ（1日前）
  prev_d1_diff INT64 OPTIONS(description = '前日 差枚'),
  prev_d1_game INT64 OPTIONS(description = '前日 ゲーム数'),
  prev_d1_payout_rate FLOAT64 OPTIONS(description = '前日 機械割'),
  
  -- 2日間（前日〜2日前）
  prev_d2_diff INT64 OPTIONS(description = '前日から2日間 総差枚'),
  prev_d2_game INT64 OPTIONS(description = '前日から2日間 総ゲーム数'),
  prev_d2_win_rate FLOAT64 OPTIONS(description = '前日から2日間 勝率'),
  prev_d2_payout_rate FLOAT64 OPTIONS(description = '前日から2日間 機械割'),
  
  -- 3日間（前日〜3日前）
  prev_d3_diff INT64 OPTIONS(description = '前日から3日間 総差枚'),
  prev_d3_game INT64 OPTIONS(description = '前日から3日間 総ゲーム数'),
  prev_d3_win_rate FLOAT64 OPTIONS(description = '前日から3日間 勝率'),
  prev_d3_payout_rate FLOAT64 OPTIONS(description = '前日から3日間 機械割'),
  
  -- 4日間（前日〜4日前）
  prev_d4_diff INT64 OPTIONS(description = '前日から4日間 総差枚'),
  prev_d4_game INT64 OPTIONS(description = '前日から4日間 総ゲーム数'),
  prev_d4_win_rate FLOAT64 OPTIONS(description = '前日から4日間 勝率'),
  prev_d4_payout_rate FLOAT64 OPTIONS(description = '前日から4日間 機械割'),
  
  -- 5日間（前日〜5日前）
  prev_d5_diff INT64 OPTIONS(description = '前日から5日間 総差枚'),
  prev_d5_game INT64 OPTIONS(description = '前日から5日間 総ゲーム数'),
  prev_d5_win_rate FLOAT64 OPTIONS(description = '前日から5日間 勝率'),
  prev_d5_payout_rate FLOAT64 OPTIONS(description = '前日から5日間 機械割'),
  
  -- 6日間（前日〜6日前）
  prev_d6_diff INT64 OPTIONS(description = '前日から6日間 総差枚'),
  prev_d6_game INT64 OPTIONS(description = '前日から6日間 総ゲーム数'),
  prev_d6_win_rate FLOAT64 OPTIONS(description = '前日から6日間 勝率'),
  prev_d6_payout_rate FLOAT64 OPTIONS(description = '前日から6日間 機械割'),
  
  -- 7日間（前日〜7日前）
  prev_d7_diff INT64 OPTIONS(description = '前日から7日間 総差枚'),
  prev_d7_game INT64 OPTIONS(description = '前日から7日間 総ゲーム数'),
  prev_d7_win_rate FLOAT64 OPTIONS(description = '前日から7日間 勝率'),
  prev_d7_payout_rate FLOAT64 OPTIONS(description = '前日から7日間 機械割'),
  
  -- 14日間（前日〜14日前）
  prev_d14_diff INT64 OPTIONS(description = '前日から14日間 総差枚'),
  prev_d14_game INT64 OPTIONS(description = '前日から14日間 総ゲーム数'),
  prev_d14_win_rate FLOAT64 OPTIONS(description = '前日から14日間 勝率'),
  prev_d14_payout_rate FLOAT64 OPTIONS(description = '前日から14日間 機械割'),
  
  -- 28日間（前日〜28日前）
  prev_d28_diff INT64 OPTIONS(description = '前日から28日間 総差枚'),
  prev_d28_game INT64 OPTIONS(description = '前日から28日間 総ゲーム数'),
  prev_d28_win_rate FLOAT64 OPTIONS(description = '前日から28日間 勝率'),
  prev_d28_payout_rate FLOAT64 OPTIONS(description = '前日から28日間 機械割'),
  
  -- 前月分（前日〜月初）
  prev_mtd_diff INT64 OPTIONS(description = '前日から当月 総差枚'),
  prev_mtd_game INT64 OPTIONS(description = '前日から当月 総ゲーム数'),
  prev_mtd_win_rate FLOAT64 OPTIONS(description = '前日から当月 勝率'),
  prev_mtd_payout_rate FLOAT64 OPTIONS(description = '前日から当月 機械割'),
  
  -- 全期間（前日〜データ開始日）
  prev_all_diff INT64 OPTIONS(description = '前日から全期間 総差枚'),
  prev_all_game INT64 OPTIONS(description = '前日から全期間 総ゲーム数'),
  prev_all_win_rate FLOAT64 OPTIONS(description = '前日から全期間 勝率'),
  prev_all_payout_rate FLOAT64 OPTIONS(description = '前日から全期間 機械割'),
  prev_all_days INT64 OPTIONS(description = '前日から全期間 集計日数')
)
PARTITION BY target_date
OPTIONS (
  description = '台番別統計データマート。当日/前日からの各期間集計。',
  labels = [('purpose', 'datamart'), ('data_type', 'machine_stats')],
  partition_expiration_days = NULL,
  require_partition_filter = FALSE
);

-- ============================================================================
-- 確認用クエリ
-- ============================================================================
-- テーブル情報の確認
-- SELECT * FROM `yobun-450512.datamart.INFORMATION_SCHEMA.TABLES` WHERE table_name = 'machine_stats';

-- カラム情報の確認
-- SELECT * FROM `yobun-450512.datamart.INFORMATION_SCHEMA.COLUMNS` WHERE table_name = 'machine_stats';
