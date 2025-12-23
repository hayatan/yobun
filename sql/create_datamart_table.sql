-- データマートテーブル作成DDL
-- 実行場所: BigQueryコンソール
-- 実行タイミング: 初回のみ（スケジュールクエリ設定前）

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
  
  -- 過去28日間の集計
  d28_diff INT64 OPTIONS(description = '28日間 総差枚'),
  d28_game INT64 OPTIONS(description = '28日間 総ゲーム数'),
  d28_win_rate FLOAT64 OPTIONS(description = '28日間 勝率'),
  d28_payout_rate FLOAT64 OPTIONS(description = '28日間 機械割'),
  
  -- 過去5日間の集計
  d5_diff INT64 OPTIONS(description = '5日間 総差枚'),
  d5_game INT64 OPTIONS(description = '5日間 総ゲーム数'),
  d5_win_rate FLOAT64 OPTIONS(description = '5日間 勝率'),
  d5_payout_rate FLOAT64 OPTIONS(description = '5日間 機械割'),
  
  -- 過去3日間の集計
  d3_diff INT64 OPTIONS(description = '3日間 総差枚'),
  d3_game INT64 OPTIONS(description = '3日間 総ゲーム数'),
  d3_win_rate FLOAT64 OPTIONS(description = '3日間 勝率'),
  d3_payout_rate FLOAT64 OPTIONS(description = '3日間 機械割'),
  
  -- 当日データ
  d1_diff INT64 OPTIONS(description = '当日 差枚'),
  d1_game INT64 OPTIONS(description = '当日 ゲーム数'),
  d1_payout_rate FLOAT64 OPTIONS(description = '当日 機械割')
)
PARTITION BY target_date
-- クラスタリングはスケジュールクエリとの互換性のため無効化
-- CLUSTER BY hole, machine_number
OPTIONS (
  description = '台番別統計データマート。日付パーティション + 店舗・台番クラスタリング。',
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

