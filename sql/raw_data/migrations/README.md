# マイグレーション手順書

## 概要

元データテーブルに `source` カラムを追加するマイグレーション。
複数データソース（スロレポ、みんレポ等）対応のための準備。

## 前提条件

- 既存データはすべてスロレポからの取得
- `source` カラムのデフォルト値は `'slorepo'`

## マイグレーション一覧

| ファイル | 対象 | 説明 |
|----------|------|------|
| `001_add_source_column.sqlite.sql` | SQLite | source カラム追加 |
| `001_add_source_column.bq.sql` | BigQuery | 全日次テーブルに source カラム追加 |

---

## 001: source カラム追加

### 1. SQLite マイグレーション

```bash
# Docker環境で実行
docker exec -it <container_name> sqlite3 /tmp/db.sqlite

# SQLiteシェル内で実行
ALTER TABLE scraped_data ADD COLUMN source TEXT NOT NULL DEFAULT 'slorepo';

# 確認
SELECT DISTINCT source FROM scraped_data;
.quit
```

### 2. BigQuery マイグレーション

#### Step 1: 対象テーブル一覧を取得

BigQueryコンソールで以下を実行：

```sql
SELECT table_name 
FROM `yobun-450512.scraped_data.INFORMATION_SCHEMA.TABLES`
WHERE table_name LIKE 'data_%'
ORDER BY table_name;
```

#### Step 2: ALTER TABLE文を一括生成

```sql
SELECT CONCAT(
  'ALTER TABLE `yobun-450512.scraped_data.', 
  table_name, 
  '` ADD COLUMN IF NOT EXISTS source STRING DEFAULT ''slorepo'';'
) AS alter_statement
FROM `yobun-450512.scraped_data.INFORMATION_SCHEMA.TABLES`
WHERE table_name LIKE 'data_%'
ORDER BY table_name;
```

#### Step 3: 生成された文を実行

Step 2の結果をコピーして、BigQueryコンソールで実行。

#### Step 4: 確認

```sql
-- カラム追加の確認
SELECT column_name, data_type 
FROM `yobun-450512.scraped_data.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'data_20250101' AND column_name = 'source';

-- データ確認
SELECT DISTINCT source FROM `yobun-450512.scraped_data.data_20250101`;
```

---

## ロールバック

### SQLite

```sql
-- SQLiteでは ALTER TABLE DROP COLUMN がサポートされていないため、
-- テーブル再作成が必要
-- バックアップからの復元を推奨
```

### BigQuery

```sql
-- カラム削除（各テーブルに対して実行）
ALTER TABLE `yobun-450512.scraped_data.data_YYYYMMDD`
DROP COLUMN source;
```

---

## 注意事項

1. マイグレーションはコード変更前に実行すること
2. マイグレーション後、一時的に `source` カラムは未使用状態になるが問題なし
3. 新しいデータ挿入時には `source` を明示的に指定すること（コード変更後）
4. BigQueryの日次テーブルは多数あるため、一括実行スクリプトを使用すること
