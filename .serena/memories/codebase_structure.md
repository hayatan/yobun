# コードベース構造

```
yobun/
├── src/                    # ソースコードルート
│   ├── api/                # APIルーティング
│   │   ├── routes/         # エンドポイント別ルーター
│   │   │   ├── corrections.js    # 手動補正API
│   │   │   ├── data-status.js    # データ状態API
│   │   │   ├── datamart.js       # データマートAPI
│   │   │   ├── dedupe.js         # 重複削除API
│   │   │   ├── failures.js       # 失敗管理API
│   │   │   ├── force-rescrape.js # 再取得API
│   │   │   ├── schedule.js       # スケジュールAPI
│   │   │   ├── scrape.js         # スクレイピングAPI
│   │   │   └── sync.js           # 同期API
│   │   └── state-manager.js      # ジョブ状態管理
│   ├── config/             # 設定ファイル
│   │   ├── constants.js          # 定数定義
│   │   ├── slorepo-config.js     # 店舗設定
│   │   └── sources/              # データソース設定
│   ├── db/                 # データベース操作
│   │   ├── bigquery/             # BigQuery関連
│   │   │   ├── init.js
│   │   │   └── operations.js
│   │   └── sqlite/               # SQLite関連
│   │       ├── corrections.js
│   │       ├── failures.js
│   │       ├── init.js
│   │       └── operations.js
│   ├── scheduler/          # スケジューラー
│   │   ├── index.js              # メインロジック
│   │   └── storage.js            # GCS永続化
│   ├── services/           # ビジネスロジック
│   │   ├── datamart/
│   │   │   └── runner.js         # データマート更新
│   │   └── slorepo/
│   │       ├── index.js
│   │       └── scraper.js        # スクレイピング処理
│   └── util/               # ユーティリティ
│       ├── common.js
│       ├── csv.js
│       ├── date.js               # JST日付ユーティリティ
│       ├── lock.js               # GCSロック機構
│       └── slorepo.js
├── sql/                    # SQLスキーマ・クエリ
│   ├── raw_data/                 # 生データスキーマ
│   │   └── schema.js             # ★Single Source of Truth
│   ├── scrape_failures/          # 失敗記録スキーマ
│   ├── manual_corrections/       # 手動補正スキーマ
│   ├── datamart/                 # データマート定義
│   └── analysis/                 # 分析クエリ
├── public/                 # フロントエンド（静的HTML）
├── deploy/                 # デプロイスクリプト
├── server.js               # Webサーバーエントリポイント
├── job.js                  # Cloud Run Jobsエントリポイント
└── Makefile                # タスクランナー
```