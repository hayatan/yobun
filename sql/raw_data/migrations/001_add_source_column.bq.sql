-- ============================================================================
-- BigQuery マイグレーション: source カラム追加
-- ============================================================================
-- 
-- 実行方法:
--   BigQueryコンソールで各テーブルに対して実行
-- 
-- 目的:
--   複数データソース対応のため、どのサイトから取得したデータかを識別する
--   既存データはすべて slorepo からの取得
-- ============================================================================

-- Step 1: 対象テーブル一覧を取得
-- 以下のクエリで対象テーブルを確認
SELECT table_name 
FROM `yobun-450512.slot_data.INFORMATION_SCHEMA.TABLES`
WHERE table_name LIKE 'data_%'
ORDER BY table_name;

-- Step 2: 各テーブルに source カラムを追加
-- YYYYMMDD を実際の日付に置換して実行
-- 例: data_20250101, data_20250102, ...

-- 以下のパターンで各テーブルに対して実行:
ALTER TABLE `yobun-450512.slot_data.data_YYYYMMDD`
ADD COLUMN IF NOT EXISTS source STRING DEFAULT 'slorepo';

-- ============================================================================
-- 一括実行用スクリプト生成クエリ
-- ============================================================================
-- 以下のクエリを実行すると、全テーブル用のALTER TABLE文が生成される
SELECT CONCAT(
  'ALTER TABLE `yobun-450512.slot_data.', 
  table_name, 
  '` ADD COLUMN IF NOT EXISTS source STRING DEFAULT ''slorepo'';'
) AS alter_statement
FROM `yobun-450512.slot_data.INFORMATION_SCHEMA.TABLES`
WHERE table_name LIKE 'data_%'
ORDER BY table_name;

-- ============================================================================
-- 確認用クエリ
-- ============================================================================
-- カラムが追加されたか確認（例: data_20250101）
-- SELECT column_name, data_type 
-- FROM `yobun-450512.slot_data.INFORMATION_SCHEMA.COLUMNS`
-- WHERE table_name = 'data_20250101' AND column_name = 'source';

-- データ確認
-- SELECT DISTINCT source FROM `yobun-450512.slot_data.data_20250101`;
