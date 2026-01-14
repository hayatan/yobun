-- ============================================================================
-- SQLite マイグレーション: source カラム追加
-- ============================================================================
-- 
-- 実行方法:
--   docker exec -it <container> sqlite3 /tmp/db.sqlite < sql/raw_data/migrations/001_add_source_column.sqlite.sql
-- 
-- 目的:
--   複数データソース対応のため、どのサイトから取得したデータかを識別する
--   既存データはすべて slorepo からの取得
-- ============================================================================

-- source カラムを追加（既存データは 'slorepo' がデフォルト値）
ALTER TABLE scraped_data ADD COLUMN source TEXT NOT NULL DEFAULT 'slorepo';

-- 確認用クエリ
-- SELECT DISTINCT source FROM scraped_data;
-- SELECT COUNT(*) FROM scraped_data WHERE source = 'slorepo';
