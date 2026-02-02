-- ============================================================================
-- 元データテーブル作成DDL（BigQuery）
-- ============================================================================
-- 実行場所: BigQueryコンソール
-- 実行タイミング: 初回のみ
-- 
-- 注意: 実際のテーブルは日付ごとに動的に作成される（data_YYYYMMDD）
--       このDDLはスキーマの正式な定義として管理する
-- ============================================================================

-- ============================================================================
-- scraped_data データセットの作成（存在しない場合）
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS `yobun-450512.scraped_data`
OPTIONS (
  location = 'US',
  description = 'スロットデータ元データ用データセット'
);

-- ============================================================================
-- テンプレートテーブル（スキーマ定義用）
-- ============================================================================
-- 実際の日次テーブル（data_YYYYMMDD）はスクレイパーが動的に作成
-- このテーブルはスキーマの参照用として作成

CREATE TABLE IF NOT EXISTS `yobun-450512.scraped_data._template` (
  -- 識別子
  id STRING NOT NULL OPTIONS(description = 'ユニークID: {date}_{hole}_{machine_number}_{source}'),
  
  -- 基本情報
  date STRING NOT NULL OPTIONS(description = '日付 (YYYY-MM-DD)'),
  hole STRING NOT NULL OPTIONS(description = '店舗名'),
  machine STRING NOT NULL OPTIONS(description = '機種名'),
  machine_number INT64 NOT NULL OPTIONS(description = '台番'),
  
  -- 実績データ
  diff INT64 OPTIONS(description = '差枚'),
  game INT64 OPTIONS(description = 'ゲーム数'),
  big INT64 OPTIONS(description = 'BB回数'),
  reg INT64 OPTIONS(description = 'RB回数'),
  combined_rate STRING OPTIONS(description = '合成確率'),
  
  -- 追加統計（現在未使用）
  max_my INT64 OPTIONS(description = 'MAX MY（未使用、0固定）'),
  max_mdia INT64 OPTIONS(description = 'MAX Mダイヤ（未使用、0固定）'),
  
  -- 算出項目
  win INT64 OPTIONS(description = '勝敗フラグ (1=勝ち, 0=負け)'),
  
  -- メタ情報
  source STRING NOT NULL DEFAULT 'slorepo' OPTIONS(description = 'データソース (slorepo, minrepo等)'),
  timestamp TIMESTAMP NOT NULL OPTIONS(description = 'レコード作成日時')
)
OPTIONS (
  description = '元データテンプレート。実際のデータは data_YYYYMMDD テーブルに格納。',
  labels = [('purpose', 'raw_data'), ('data_type', 'scraped_data')]
);

-- ============================================================================
-- 確認用クエリ
-- ============================================================================
-- テンプレートスキーマの確認
-- SELECT * FROM `yobun-450512.scraped_data.INFORMATION_SCHEMA.COLUMNS` 
-- WHERE table_name = '_template';

-- 日次テーブル一覧の確認
-- SELECT table_name FROM `yobun-450512.scraped_data.INFORMATION_SCHEMA.TABLES`
-- WHERE table_name LIKE 'data_%'
-- ORDER BY table_name DESC;

-- データソース別の件数確認（日次テーブル）
-- SELECT source, COUNT(*) as count 
-- FROM `yobun-450512.scraped_data.data_20250101`
-- GROUP BY source;
