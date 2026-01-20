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
- スキーマ → `sql/raw_data/schema.js`（Single Source of Truth）

## 実装方針

### データベース

- **SQLite**: プライマリストレージ（Litestreamでバックアップ）
- **BigQuery**: 分析用DB（SQLiteと同期）

### ジョブ管理

- GCSベースのロック機構（排他制御）
- スケジュール設定はGCSに永続化
- ジョブ失敗時も確実にロック解放（`finally` 節）

### スクレイピング

- Puppeteer + Stealth プラグイン使用
- エラー継続オプション（`continueOnError`）
- 優先度フィルタ（`priorityFilter`）

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
