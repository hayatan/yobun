# Yobun - スロットデータ分析システム

パチスロ店舗のデータを自動収集・分析するシステム

## 概要

- スロレポからのデータスクレイピング
- BigQueryでのデータ蓄積・分析
- データマートによる統計情報の自動生成
- Webフロントエンドでの手動実行・状況確認

## クイックスタート

### 前提条件

- Docker
- Google Cloud認証情報（`.env.production`に設定）

### ローカル実行

```bash
# Dockerイメージのビルド
make build

# Webサーバー起動（フロントエンド）
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
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Cloud          │     │  Cloud Run      │     │  BigQuery       │
│  Scheduler      │────▶│  Jobs           │────▶│  (raw_data)     │
│  (JST基準)      │     │  (スクレイピング)│     │                 │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                              ┌──────────────────────────┘
                              │
                              ▼
                        ┌─────────────────┐
                        │  BigQuery       │
                        │  (datamart)     │
                        │  ・machine_stats│
                        └─────────────────┘
```

### データフロー

1. **スクレイピング**: スロレポからデータ取得
2. **SQLite保存**: ローカルキャッシュ（Litestreamでバックアップ）
3. **BigQuery同期**: 分析用DBに保存
4. **データマート更新**: 統計情報を自動生成

### スケジュール（自動化時）

| 時刻（JST） | 対象 | 説明 |
|------------|------|------|
| 7:00-8:00（10分おき） | 優先店舗 | アイランド秋葉原、エスパス秋葉原 |
| 8:30, 10:00, 12:30 | 全店舗 | 未取得分を取得 |

## ディレクトリ構成

```
yobun/
├── src/
│   ├── api/           # APIルーティング
│   │   ├── routes/    # エンドポイント別ルーター
│   │   └── state-manager.js
│   ├── config/        # 設定ファイル
│   │   ├── constants.js
│   │   ├── slorepo-config.js  # 店舗設定
│   │   └── sources/   # データソース設定
│   ├── db/            # データベース操作
│   │   ├── bigquery/
│   │   └── sqlite/
│   ├── services/      # ビジネスロジック
│   │   ├── slorepo/   # スクレイピング
│   │   └── datamart/  # データマート更新
│   └── util/          # ユーティリティ
│       ├── date.js    # JST日付ユーティリティ
│       └── lock.js    # GCSロック機構
├── sql/               # SQLスキーマ・クエリ
│   ├── raw_data/      # 生データスキーマ
│   ├── datamart/      # データマート定義
│   └── analysis/      # 分析クエリ
├── public/            # フロントエンド
│   └── dashboard.html # データ取得状況確認
├── deploy/            # デプロイスクリプト
├── server.js          # Webサーバーエントリポイント
├── job.js             # Cloud Run Jobsエントリポイント
└── Makefile
```

## API エンドポイント

| エンドポイント | メソッド | 説明 |
|---------------|---------|------|
| `/` | GET | トップページ |
| `/dashboard` | GET | データ取得状況ダッシュボード |
| `/status` | GET | スクレイピング状態 |
| `/pubsub` | POST | スクレイピング開始 |
| `/api/data-status` | GET | データ取得状況API |
| `/api/lock` | GET | ロック状態確認 |
| `/util/sync` | GET/POST | SQLite→BigQuery同期 |
| `/util/force-rescrape` | GET/POST | 強制再取得 |
| `/health` | GET | ヘルスチェック |

## ドキュメント

- [sql/AGENTS.md](sql/AGENTS.md) - SQL開発ガイドライン
- [sql/raw_data/README.md](sql/raw_data/README.md) - 生データスキーマ
- [sql/datamart/machine_stats/README.md](sql/datamart/machine_stats/README.md) - 機種統計データマート
- [sql/analysis/README.md](sql/analysis/README.md) - 分析クエリ
- [sql/analysis/ROADMAP.md](sql/analysis/ROADMAP.md) - 分析ロードマップ
- [deploy/README.md](deploy/README.md) - デプロイ手順

## 将来構想

### Phase 1: スクレイピング自動化 ✅

- Cloud Run Jobsによる自動実行
- GCSロックによる排他制御
- データ取得状況ダッシュボード

### Phase 2: パイプライン強化

- Eventarcによるイベント駆動型データマート更新
- 狙い台分析用データマートの追加
- 複数データソース対応（みんレポなど）

### Phase 3: 分析高度化

- 機械学習による狙い台予測
- 戦略マッチングの自動化
- アラート通知（Slack/LINE）

## 開発

### 環境変数

```bash
# .env.production
GOOGLE_CLOUD_PROJECT=yobun-450512
GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json
NODE_ENV=production
```

### コマンド一覧

```bash
make help  # コマンド一覧を表示
```

## ライセンス

Private
