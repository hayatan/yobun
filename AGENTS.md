# Yobun エージェント向けガイドライン

AIエージェント向けの開発ガイドライン。コーディング規約の詳細は `.cursor/rules/yobun.mdc` を参照。

## プロジェクト概要

パチスロデータの自動収集・分析システム。

- **データソース**: スロレポ（Webスクレイピング）
- **ストレージ**: SQLite（プライマリ）→ BigQuery（分析用）
- **実行環境**: Docker

## アーキテクチャ

```
スロレポ → Puppeteer → SQLite → BigQuery → データマート
                         ↓
                   Litestream → GCS（バックアップ）
```

**データフロー**:
1. スケジューラーがジョブを実行
2. Puppeteer + Stealthでスクレイピング
3. SQLiteに保存（プライマリ）
4. GCS経由Load JobでBigQueryに同期
5. データマート更新（統計情報生成）

## 実装方針

### データベース

- **SQLite**: プライマリストレージ（Litestreamでバックアップ）
- **BigQuery**: 分析用DB（SQLiteと同期）
- **BigQuery同期方式**: GCS経由のLoad Job使用
  - データをGCS（`youbun-sqlite/temp/`）に一時アップロード
  - 単一店舗: DELETE後にLoad Job (WRITE_APPEND)
  - 複数店舗: Load Job (WRITE_TRUNCATE)
  - 重複が発生しない設計

### スクレイピング

- Puppeteer + Stealth プラグイン
- `continueOnError`: エラー発生時も処理継続
- `priorityFilter`: 店舗の優先度フィルタ
- **リトライ**: 429/5xxエラー時、指数バックオフで最大3回
- **エラー分類**: cloudflare/timeout/network/parse/http_error/unknown
- 失敗時は `scrape_failures` テーブルに自動記録

### 失敗管理・手動補正

- **失敗記録**: スクレイピング失敗を `scrape_failures` に自動記録
- **手動補正**: 管理画面でクリップボード貼り付け → `manual_corrections` に保存
- **フォールバック**: 再取得失敗時、`manual_corrections` から自動復元
- DB: `src/db/sqlite/failures.js`, `src/db/sqlite/corrections.js`

### イベント管理

- **イベント**: 店舗のイベント情報（LINE告知、特定日など）を管理
- **イベントタイプ**: イベント種類のマスターデータ（フロント選択肢用）
- **BigQuery同期**: 分析用に `slot_data.events` テーブルに同期
- DB: `src/db/sqlite/events.js`, `src/db/sqlite/event-types.js`
- API: `src/api/routes/events.js`, `src/api/routes/event-types.js`
- UI: `public/events.html`

### スケジューラー

- GCSベースのロック機構（排他制御）
- スケジュール設定はGCSに永続化（`youbun-sqlite/schedules.json`）
- ジョブ失敗時も確実にロック解放（`finally` 節）
- タイプ: `daily`（毎日指定時刻）/ `interval`（指定間隔）

### データマート

- SQLファイル実行でBigQueryに統計情報を生成
- `target_date`: 実行日の1日前を対象
- MERGEで更新（既存データは上書き）
- SQL: `sql/datamart/machine_stats/`

### 重複データ削除

- **BigQuery**: `CREATE OR REPLACE TABLE` + `GROUP BY id` で重複削除
- **SQLite**: PRIMARY KEY制約で基本的に重複なし
- API/UI: `/util/dedupe`

## 設定ファイル

| ファイル | 内容 |
|---------|------|
| `src/config/constants.js` | 定数定義 |
| `src/config/slorepo-config.js` | 店舗設定 |
| `sql/raw_data/schema.js` | 生データスキーマ（Single Source of Truth） |
| `sql/scrape_failures/schema.js` | 失敗記録スキーマ |
| `sql/manual_corrections/schema.js` | 手動補正スキーマ |
| `sql/events/schema.js` | イベントスキーマ（SQLite/BigQuery両対応） |
| `sql/event_types/schema.js` | イベントタイプスキーマ（SQLiteのみ） |

## 変更時の注意

- **スキーマ変更** → マイグレーションファイル作成（`sql/*/migrations/`）
- **新機能追加** → `README.md` を更新
- **SQL変更** → `sql/AGENTS.md` を参照
- **店舗追加** → `src/config/slorepo-config.js` を編集

## 参照ドキュメント

| ドキュメント | 内容 |
|-------------|------|
| [README.md](README.md) | プロジェクト詳細・API仕様・機能一覧 |
| [.cursor/rules/yobun.mdc](.cursor/rules/yobun.mdc) | コーディング規約・命名規則・コード例 |
| [sql/AGENTS.md](sql/AGENTS.md) | SQL開発ガイドライン |
| [deploy/README.md](deploy/README.md) | デプロイ手順 |
