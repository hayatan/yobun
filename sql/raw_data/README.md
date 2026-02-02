# 元データ（Raw Data）

## 概要

スクレイピングで取得したスロットデータの元データを管理します。

## ファイル構成

```
sql/raw_data/
├── README.md                    # このファイル
├── schema.js                    # 共通スキーマ定義（SQLite/BQ両対応）
├── create_raw_data_table.sql    # BigQuery DDL
└── migrations/                  # マイグレーションファイル
    ├── README.md                # マイグレーション手順書
    ├── 001_add_source_column.sqlite.sql
    └── 001_add_source_column.bq.sql
```

## テーブル構造

| カラム | 型 | 説明 |
|--------|-----|------|
| id | STRING | ユニークID: `{date}_{hole}_{machine_number}_{source}` |
| date | STRING | 日付 (YYYY-MM-DD) |
| hole | STRING | 店舗名 |
| machine | STRING | 機種名 |
| machine_number | INT64 | 台番 |
| diff | INT64 | 差枚 |
| game | INT64 | ゲーム数 |
| big | INT64 | BB回数 |
| reg | INT64 | RB回数 |
| combined_rate | STRING | 合成確率 |
| max_my | INT64 | MAX MY（未使用、0固定） |
| max_mdia | INT64 | MAX Mダイヤ（未使用、0固定） |
| win | INT64 | 勝敗フラグ (1=勝ち, 0=負け) |
| source | STRING | データソース (slorepo, minrepo等) |
| timestamp | TIMESTAMP | レコード作成日時 |

## データソース

| source | サイト | 備考 |
|--------|--------|------|
| slorepo | スロレポ | メインソース |
| minrepo | みんレポ | 将来対応予定 |

## 格納場所

- **BigQuery**: `yobun-450512.scraped_data.data_YYYYMMDD`（日付ごとのテーブル）
- **SQLite**: `scraped_data` テーブル（Litestream経由でGCSにバックアップ）

## スキーマ定義

### 正式定義

`sql/raw_data/schema.js` がスキーマの正式な定義場所です。

### コードからの参照

```javascript
import { RAW_DATA_SCHEMA } from '../../sql/raw_data/schema.js';

// BigQueryスキーマを取得
const bqSchema = RAW_DATA_SCHEMA.toBigQuerySchema();

// SQLite CREATE TABLE文を取得
const sqliteCreate = RAW_DATA_SCHEMA.toSQLiteCreateTable('scraped_data');

// ID生成
const id = RAW_DATA_SCHEMA.generateId('2025-01-14', 'アイランド秋葉原店', 123, 'slorepo');

// カラム名一覧
const columns = RAW_DATA_SCHEMA.getColumnNames();

// 必須カラム一覧
const requiredColumns = RAW_DATA_SCHEMA.getRequiredColumns();
```

## マイグレーション

スキーマ変更時は `migrations/` ディレクトリにマイグレーションファイルを追加してください。

詳細は `migrations/README.md` を参照。

## 関連ファイル

- `src/db/bigquery/operations.js` - BigQuery操作（スキーマを参照）
- `src/db/sqlite/operations.js` - SQLite操作（スキーマを参照）
- `sql/datamart/` - データマート（この元データを集計）
