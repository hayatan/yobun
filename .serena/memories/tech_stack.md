# 技術スタック

## バックエンド
- **Node.js** - ES6モジュール使用 (`type: module`)
- **Express** - Webサーバー・API
- **Puppeteer + Stealth** - Webスクレイピング
- **node-cron** - スケジューラー

## データベース
- **SQLite** - プライマリストレージ
- **Litestream** - SQLiteのGCSバックアップ
- **BigQuery** - 分析用DB

## クラウド (Google Cloud)
- **Cloud Storage (GCS)** - SQLiteバックアップ、一時ファイル、スケジュール設定
- **BigQuery** - 分析用データウェアハウス
- **Cloud Run** - 本番実行環境

## フロントエンド
- **HTML/CSS/JavaScript** - 静的ファイル（`public/`）
- vanilla JS（フレームワークなし）

## 開発ツール
- **Docker** - 実行環境（ローカル直接実行は非推奨）
- **Make** - タスクランナー
- **dotenv** - 環境変数管理

## 主要ライブラリ
- `@google-cloud/bigquery` - BigQuery操作
- `@google-cloud/storage` - GCS操作
- `date-fns` / `date-fns-tz` - 日付処理（JST対応）
- `csv-parse` / `csv-parser` - CSV処理