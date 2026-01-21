# Yobun エージェント向けガイドライン

このドキュメントはAIエージェント向けの開発ガイドラインです。
詳細なルールは `.cursor/rules/yobun.mdc` を参照してください。

## プロジェクト概要

パチスロデータの自動収集・分析システムです。

- **データソース**: スロレポ（Webスクレイピング）
- **ストレージ**: SQLite（プライマリ）→ BigQuery（分析用）
- **実行環境**: Docker（ローカル実行）

## コーディング規約

### 基本方針

- ES6モジュール使用（`.js` 拡張子を明示）
- `async/await` + `try/catch` でエラーハンドリング
- ログ形式: `[${date}][${hole.name}] メッセージ`

### 設定とスキーマ

- 定数 → `src/config/constants.js`
- 店舗設定 → `src/config/slorepo-config.js`
- スキーマ:
  - `sql/raw_data/schema.js` - 生データ（Single Source of Truth）
  - `sql/scrape_failures/schema.js` - 失敗記録
  - `sql/manual_corrections/schema.js` - 手動補正データ

## 実装方針

### データベース

- **SQLite**: プライマリストレージ（Litestreamでバックアップ）
- **BigQuery**: 分析用DB（SQLiteと同期）
- **BigQuery同期方式**: GCS経由のLoad Job使用（ストリーミングINSERT廃止）
  - データをGCS（`youbun-sqlite/temp/`）に一時アップロード
  - 単一店舗データ: DELETE後にLoad Job (WRITE_APPEND)
  - 複数店舗データ: Load Job (WRITE_TRUNCATE)
  - ストリーミングバッファの問題を完全回避、重複が発生しない

### ジョブ管理

- GCSベースのロック機構（排他制御）
- スケジュール設定はGCSに永続化
- ジョブ失敗時も確実にロック解放（`finally` 節）

### スクレイピング

- Puppeteer + Stealth プラグイン使用
- エラー継続オプション（`continueOnError`）
- 優先度フィルタ（`priorityFilter`）
- エラー発生時は `scrape_failures` テーブルに記録
- **リトライ機能**: レートリミット（429）やサーバーエラー（5xx）発生時、指数バックオフで最大3回リトライ

### 失敗管理・手動補正

- **失敗記録**: スクレイピング失敗時に `scrape_failures` に自動記録
- **手動補正**: 管理画面からクリップボード貼り付けでデータを補正
- **フォールバック**: 強制再取得で失敗時、`manual_corrections` から自動復元
- DB操作: `src/db/sqlite/failures.js`, `src/db/sqlite/corrections.js`
- API: `/api/failures`, `/api/corrections`

### 重複データ削除

- **BigQuery重複削除**: 期間指定で重複データを削除（`CREATE OR REPLACE TABLE` + `GROUP BY id`）
- **SQLite重複削除**: PRIMARY KEY制約で基本的に重複なし（念のため機能あり）
- **重複チェック**: 期間指定で重複状況を確認
- API: `/util/dedupe`
- UI: `/util/dedupe`（共通ヘッダーからアクセス可能）

## 変更時の注意

- スキーマ変更 → マイグレーションファイル作成
- 新機能追加 → README.md を更新
- SQL変更 → `sql/AGENTS.md` を参照

## 参照ドキュメント

| ドキュメント | 内容 |
|-------------|------|
| `README.md` | プロジェクト詳細・API仕様・アーキテクチャ |
| `sql/AGENTS.md` | SQL開発ガイドライン |
| `deploy/README.md` | デプロイ手順 |
| `.cursor/rules/yobun.mdc` | 詳細なコーディングルール |
