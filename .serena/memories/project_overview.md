# Yobun プロジェクト概要

## 目的
パチスロ店舗のデータを自動収集・分析するシステム

## 主要機能
- スロレポからのデータスクレイピング
- SQLite（プライマリ）→ BigQuery（分析用）でのデータ蓄積
- データマートによる統計情報の自動生成
- Webダッシュボードでの管理・監視

## データフロー
1. スケジューラーがジョブを実行
2. Puppeteer + Stealthでスクレイピング
3. SQLiteに保存（プライマリ）
4. GCS経由Load JobでBigQueryに同期
5. データマート更新（統計情報生成）

## 実行環境
- **ローカル**: Docker必須
- **クラウド**: Google Cloud Run

## 重要なドキュメント
- `AGENTS.md` - エージェント向けガイドライン
- `.cursor/rules/yobun.mdc` - コーディング規約
- `sql/AGENTS.md` - SQL開発ガイドライン