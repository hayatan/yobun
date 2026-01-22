# Yobun - スロットデータ分析システム

パチスロ店舗のデータを自動収集・分析するシステム

## 概要

- スロレポからのデータスクレイピング
- SQLite（プライマリ）→ BigQuery（分析用）でのデータ蓄積
- データマートによる統計情報の自動生成
- Webダッシュボードでの管理・監視

## クイックスタート

### 前提条件

- Docker
- Google Cloud認証情報（`.env.production`に設定）

### ローカル実行

```bash
# Dockerイメージのビルド
make build

# Webサーバー起動（スケジューラー含む）
make run-docker

# ブラウザで http://localhost:8080 にアクセス
```

### Job実行（Cloud Run Jobs互換）

```bash
# 優先店舗のみスクレイピング
make run-job-priority

# 全店舗の未取得分をスクレイピング
make run-job-normal
```

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│  ローカルPC (Docker)                                        │
│  ┌─────────────────┐     ┌─────────────────┐               │
│  │  Express Server │────▶│  Scheduler      │               │
│  │  (Dashboard)    │     │  (node-cron)    │               │
│  └─────────────────┘     └────────┬────────┘               │
│           │                       │                        │
│           ▼                       ▼                        │
│  ┌─────────────────┐     ┌─────────────────┐               │
│  │  SQLite         │◀───│  Puppeteer      │               │
│  │  (Litestream)   │     │  Scraper        │               │
│  └────────┬────────┘     └─────────────────┘               │
└───────────┼─────────────────────────────────────────────────┘
            │
            ▼
┌───────────────────────────────────────────────────────────────┐
│  Google Cloud                                                 │
│  ┌─────────────────┐     ┌─────────────────┐                 │
│  │  Cloud Storage  │     │  BigQuery       │                 │
│  │  - SQLite backup│     │  - raw_data     │                 │
│  │  - Lock file    │     │  - datamart     │                 │
│  │  - Schedules    │     │                 │                 │
│  └─────────────────┘     └─────────────────┘                 │
└───────────────────────────────────────────────────────────────┘
```

### データフロー

1. **スケジューラー**: 設定された時刻にジョブを実行
2. **スクレイピング**: スロレポからデータ取得（Puppeteer + Stealth）
3. **SQLite保存**: プライマリストレージに保存
4. **BigQuery同期**: Load Jobで分析用DBに同期（重複防止）
5. **データマート更新**: 統計情報を自動生成

### BigQuery同期の仕組み

SQLiteからBigQueryへの同期はGCS経由のLoad Jobを使用し、重複が発生しない設計になっています。

**処理フロー:**
1. データをNDJSON形式でGCS（`youbun-sqlite/temp/`）に一時アップロード
2. BigQuery Load Jobでテーブルにロード
3. 一時ファイルを削除

**同期モード:**
- **単一店舗データ**: DELETE後にLoad Job (WRITE_APPEND)（店舗+日付単位で既存データを置換）
- **複数店舗データ**: Load Job (WRITE_TRUNCATE)（日付テーブル全体を置換）

**利点:**
- ストリーミングバッファを使用しないため、DML操作が常に可能
- 重複が確実に発生しない

## 機能一覧

### ダッシュボード（トップページ）

- データ取得状況の確認
- 生データの削除
- ロックの強制解除

### スケジュール管理

- ジョブの有効/無効切り替え
- 複数スケジュールの設定（日次/間隔）
- 対象日付範囲の設定
- データマート自動更新オプション
- 手動実行/停止

### 失敗管理・手動補正

スクレイピング失敗時にデータを手動補正できる機能。

- **失敗一覧**: スクレイピング失敗の記録・管理
  - フィルタ（日付範囲、店舗、ステータス）
  - エラー種別表示（cloudflare/timeout/network/parse等）
- **補正入力**: 手動でデータを補正
  - クリップボード貼り付け（スロレポのテーブルをコピー→パース）
  - iframe参照（オプション/スロレポを横に表示）
  - プレビュー＆登録
- **補正履歴**: 過去の補正データの確認・削除
- **フォールバック機能**: 再取得で失敗時、手動補正データから自動復元

### データマート管理

- 統計データの確認
- データの削除/再実行

### ユーティリティ

- **SQLite → BigQuery 同期**: Load Jobを使用した重複防止同期
- **再取得**: 日付範囲・店舗指定での再スクレイピング
- **重複データ削除**: 既存の重複データをクリーンアップ（BigQuery/SQLite）

## ディレクトリ構成

```
yobun/
├── src/
│   ├── api/              # APIルーティング
│   │   ├── routes/       # エンドポイント別ルーター
│   │   └── state-manager.js
│   ├── config/           # 設定ファイル
│   │   ├── constants.js
│   │   ├── slorepo-config.js  # 店舗設定
│   │   └── sources/      # データソース設定
│   ├── db/               # データベース操作
│   │   ├── bigquery/
│   │   └── sqlite/
│   ├── scheduler/        # スケジューラー
│   │   ├── index.js      # メインロジック
│   │   └── storage.js    # GCS永続化
│   ├── services/         # ビジネスロジック
│   │   ├── slorepo/      # スクレイピング
│   │   └── datamart/     # データマート更新
│   └── util/             # ユーティリティ
│       ├── date.js       # JST日付ユーティリティ
│       └── lock.js       # GCSロック機構
├── sql/                  # SQLスキーマ・クエリ
│   ├── raw_data/         # 生データスキーマ
│   ├── scrape_failures/  # 失敗記録スキーマ
│   ├── manual_corrections/ # 手動補正スキーマ
│   ├── datamart/         # データマート定義
│   └── analysis/         # 分析クエリ
├── public/               # フロントエンド
│   ├── dashboard.html    # ダッシュボード（トップ）
│   ├── schedule.html     # スケジュール管理
│   ├── datamart.html     # データマート管理
│   ├── failures.html     # 失敗管理・手動補正
│   ├── util/
│   │   ├── sync.html     # SQLite→BigQuery同期
│   │   └── dedupe.html   # 重複データ削除
│   └── js/
│       └── status-header.js  # 共通ヘッダー
├── deploy/               # デプロイスクリプト
├── server.js             # Webサーバーエントリポイント
├── job.js                # Cloud Run Jobsエントリポイント
└── Makefile
```

## API エンドポイント

### ページ

| エンドポイント | 説明 |
|---------------|------|
| `/` | ダッシュボード（トップページ） |
| `/dashboard` | ダッシュボード（エイリアス） |
| `/schedule` | スケジュール管理 |
| `/datamart` | データマート管理 |
| `/failures` | 失敗管理・手動補正 |
| `/util/sync` | SQLite→BigQuery同期 |
| `/util/dedupe` | 重複データ削除 |

### API

| エンドポイント | メソッド | 説明 |
|---------------|---------|------|
| `/status` | GET | スクレイピング状態 |
| `/pubsub` | POST | スクレイピング開始 |
| `/api/data-status` | GET | データ取得状況 |
| `/api/data-status/:date/:hole` | GET | 特定日付・店舗のデータ詳細 |
| `/api/data-status/raw` | DELETE | 生データ削除 |
| `/api/lock` | GET | ロック状態確認 |
| `/api/lock` | DELETE | ロック強制解除 |
| `/api/schedules` | GET | スケジュール一覧 |
| `/api/schedules/:jobId` | PUT | ジョブ更新 |
| `/api/schedules/:jobId/run` | POST | ジョブ手動実行 |
| `/api/schedules/stop` | POST | ジョブ停止 |
| `/api/schedules/:jobId/schedules` | POST | スケジュール追加 |
| `/api/schedules/:jobId/schedules/:id` | PUT/DELETE | スケジュール更新/削除 |
| `/api/datamart/status` | GET | データマート状態 |
| `/api/datamart/status/job` | GET | データマートジョブ状態 |
| `/api/datamart/delete` | DELETE | データマート削除 |
| `/util/force-rescrape` | POST | データ再取得（日付範囲対応） |
| `/util/force-rescrape/status` | GET | 再取得状態 |
| `/api/datamart/run` | POST | データマート再実行 |
| `/api/failures` | GET | 失敗一覧取得（フィルタ対応） |
| `/api/failures/stats` | GET | 失敗統計取得 |
| `/api/failures/:id` | GET | 失敗詳細取得 |
| `/api/failures/:id` | PATCH | 失敗ステータス更新 |
| `/api/failures/:id` | DELETE | 失敗レコード削除 |
| `/api/failures/bulk` | DELETE | 失敗一括削除 |
| `/api/corrections` | POST | 手動補正データ登録 |
| `/api/corrections` | GET | 手動補正一覧取得 |
| `/api/corrections/summary` | GET | 補正サマリー取得 |
| `/api/corrections/parse` | POST | クリップボードデータパース |
| `/api/corrections/:id` | DELETE | 手動補正削除 |
| `/api/corrections/bulk` | DELETE | 手動補正一括削除 |
| `/util/dedupe/check` | GET | BigQuery重複チェック（期間指定） |
| `/util/dedupe/bigquery` | POST | BigQuery重複削除（期間指定） |
| `/util/dedupe/sqlite` | POST | SQLite重複削除 |
| `/util/dedupe/sqlite/check` | GET | SQLite重複チェック |
| `/util/dedupe/status` | GET | 重複削除処理状態 |
| `/health` | GET | ヘルスチェック |

## スケジューラー設定

スケジュールはGCS（`youbun-sqlite/schedules.json`）に永続化されます。

### スケジュールタイプ

- **daily**: 毎日指定時刻に実行
- **interval**: 指定時間間隔で実行

### ジョブオプション

| オプション | 説明 |
|-----------|------|
| `enabled` | ジョブの有効/無効 |
| `dateRange.from` | 対象日付の開始（N日前） |
| `dateRange.to` | 対象日付の終了（N日前） |
| `runDatamartAfter` | スクレイピング後にデータマート更新 |
| `priorityFilter` | 店舗の優先度フィルタ（high/normal/low） |

## ドキュメント

- [AGENTS.md](AGENTS.md) - エージェント向けガイドライン
- [sql/AGENTS.md](sql/AGENTS.md) - SQL開発ガイドライン
- [sql/raw_data/README.md](sql/raw_data/README.md) - 生データスキーマ
- [sql/datamart/machine_stats/README.md](sql/datamart/machine_stats/README.md) - 機種統計データマート
- [sql/analysis/README.md](sql/analysis/README.md) - 分析クエリ
- [deploy/README.md](deploy/README.md) - デプロイ手順

## 開発

### 環境変数

```bash
# .env.production
GOOGLE_CLOUD_PROJECT=yobun-450512
GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json
NODE_ENV=production
ENABLE_SCHEDULER=true  # スケジューラーの有効化（デフォルト: true）
```

### コマンド一覧

```bash
make help  # コマンド一覧を表示
```

## ライセンス

Private
