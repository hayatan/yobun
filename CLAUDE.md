# Yobun プロジェクトガイドライン

コードの変更時はこのドキュメント含め、各ドキュメント（README.md、sql/AGENTS.md 等）と常に整合性を保つようにドキュメントも常に保守してください。

## プロジェクト概要

パチスロデータの自動収集・分析システム。

- **データソース**: スロレポ（Webスクレイピング）
- **ストレージ**: SQLite（プライマリ）→ BigQuery（分析用）
- **実行環境**: Docker（ローカル）/ Cloud Run（公開）

## アーキテクチャ

```
ローカル (Docker)
スロレポ → Puppeteer → SQLite → BigQuery → データマート
                         ↓
                   Litestream → GCS（バックアップ）
                                    ↓
                              Cloud Run Service
                              (READONLY_MODE=true)
                                    ↓
                              ユーザー（ヒートマップ閲覧）
```

**運用モード**:
- **ローカル（Docker）**: スクレイピング・データ収集（書き込み可能）
- **Cloud Run Service**: 読み取り専用でヒートマップを公開（書き込み不可）

**データフロー（ローカル）**:
1. スケジューラーがジョブを実行
2. Puppeteer + Stealthでスクレイピング
3. SQLiteに保存（プライマリ）
4. GCS経由Load JobでBigQueryに同期
5. データマート更新（統計情報生成）

**デプロイフロー**:
1. GitHub mainブランチにpush
2. Cloud Runの継続的デプロイが自動実行（ビルド・デプロイ）
3. Cloud Run Serviceが更新される

## プロジェクト構造

### ディレクトリ構造
- `src/`: ソースコード
  - `api/`: APIルーティングと状態管理
    - `routes/`: エンドポイント別ルーター
    - `state-manager.js`: ジョブ状態管理
  - `config/`: 設定ファイル
    - `constants.js`: 定数定義
    - `sources/`: データソース別設定
    - `slorepo-config.js`: 店舗設定
    - `heatmap-layouts/`: ヒートマップレイアウト（storage.js のみ、実体はGCS）
  - `db/`: データベース関連
    - `sqlite/`: SQLite関連（プライマリ）
    - `bigquery/`: BigQuery関連（分析用）
  - `services/`: ビジネスロジック
    - `slorepo/`: スクレイピング処理
    - `datamart/`: データマート更新
  - `scheduler/`: スケジューラー
  - `util/`: 共通ユーティリティ
- `sql/`: SQLスキーマとマイグレーション
  - `raw_data/`: 生データスキーマ
  - `scrape_failures/`: 失敗記録スキーマ
  - `manual_corrections/`: 手動補正スキーマ
  - `events/`: イベントスキーマ
  - `event_types/`: イベントタイプスキーマ
  - `datamart/`: データマートSQL
  - `machine_summary/`: 機種サマリークエリ
  - `heatmap/`: ヒートマップクエリ
  - `analysis/`: 分析クエリ
- `public/`: 静的ファイル（HTML）

### ファイル命名規則
- スネークケース (`snake_case`) またはケバブケース (`kebab-case`) を使用

## コーディング規約

### モジュール
- ES6モジュール（`import`/`export`）を使用
- ファイル拡張子 `.js` を明示的に指定

### 非同期処理
- `async/await` + `try/catch` で統一

### データ処理
- 数値データの整形は `util/common.js` に集約
- 配列操作は `map`, `filter`, `reduce` を優先
- データには必ず `source` フィールドを含める

### ログ出力
- 日付とホール名を明示的に表示: `[${date}][${hole.name}] ...`
- エラーメッセージは具体的に記述
- デバッグ情報は本番環境では出力しない

### 設定管理
- 環境変数は `dotenv` で管理
- 定数は `src/config/constants.js` に集約
- ホール設定は `src/config/slorepo-config.js` に集約

## 実装方針

### データベース
- **SQLite**: プライマリストレージ（Litestreamでバックアップ）
- **BigQuery**: 分析用DB（SQLiteと同期）
- **BigQuery同期方式**: GCS経由のLoad Job使用
  - データをGCS（`youbun-sqlite/temp/`）に一時アップロード
  - 単一店舗: DELETE後にLoad Job (WRITE_APPEND)
  - 複数店舗: Load Job (WRITE_TRUNCATE)
  - 重複が発生しない設計
- スキーマは `sql/raw_data/schema.js` で一元管理（Single Source of Truth）

### スクレイピング
- Puppeteer + Stealth プラグイン
- `continueOnError`: エラー発生時も処理継続
- `priorityFilter`: 店舗の優先度フィルタ（high/normal/low/all）
- **リトライ**: 429/5xxエラー時、指数バックオフで最大3回
- **エラー分類**: cloudflare/timeout/network/parse/http_error/unknown
- 失敗時は `scrape_failures` テーブルに自動記録

### 失敗管理・手動補正
- **失敗記録**: スクレイピング失敗を `scrape_failures` に自動記録
- **手動補正**: 管理画面でクリップボード貼り付け → `manual_corrections` に保存
- **フォールバック**: 再取得失敗時、`manual_corrections` から自動復元
- DB: `src/db/sqlite/failures.js`, `src/db/sqlite/corrections.js`

### イベント管理
- 店舗のイベント情報（LINE告知、特定日など）を管理
- **イベントタイプ**: イベント種類のマスターデータ（フロント選択肢用）
- **BigQuery同期**: 分析用に `scraped_data.events` テーブルに同期
- DB: `src/db/sqlite/events.js`, `src/db/sqlite/event-types.js`
- API: `src/api/routes/events.js`, `src/api/routes/event-types.js`
- UI: `public/events.html`

### ヒートマップ
- **ストレージ**: GCS のみ。`layouts/{hole-slug}/{floor-slug}.json`（ローカルレイアウトファイルは廃止）
- **マルチフロア**: 1店舗で複数レイアウト（1F / 2F 等）を管理。識別子は `hole` + `floor`
- **データ可視化**: 台別統計データをフロアレイアウト上に表示（店舗・フロア選択）
- **レイアウトエディタ**: 店舗・フロア選択、新規作成（POST）、セルのマージ・分割、台番号配置
  - **パフォーマンス最適化**: インクリメンタルDOM更新、空間インデックス（`cellSpatialIndex`）による O(1) セル検索
  - **描画戦略**: セル選択・プロパティ変更・ドラッグ等は差分更新、マージ変更・Undo/Redo 等はフルリビルド
  - **計測基盤**: `?perf=true` で PerfLogger / FPSMonitor を有効化
- **レイアウト JSON v2.0**: `version`, `hole`, `floor`, `grid`, `cells`。既存移行は `scripts/migrate-layouts-to-floors.js`
- API: `src/api/routes/heatmap.js`（GET/PUT/POST/DELETE `/api/heatmap/layouts/:hole/:floor`、GET `/api/heatmap/holes`）
- レイアウト: `src/config/heatmap-layouts/storage.js`
- UI: `public/heatmap.html`, `public/heatmap-editor.html`

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

## APIエンドポイント

ルーティングは `src/api/routes/` で管理。状態管理は `src/api/state-manager.js` で集中管理。

- **スクレイピング**: `POST /pubsub`, `GET /status`
- **同期**: `POST /util/sync`, `GET /util/sync/status`
- **再取得**: `POST /util/force-rescrape`, `GET /util/force-rescrape/status`
- **データ状態**: `GET /api/data-status`, `DELETE /api/data-status/raw`
- **失敗管理**: `GET/PATCH/DELETE /api/failures`, `GET /api/failures/stats`
- **手動補正**: `POST/GET/DELETE /api/corrections`, `POST /api/corrections/parse`
- **重複削除**: `GET/POST /util/dedupe/*`
- **スケジュール**: `GET/PUT/POST/DELETE /api/schedules/*`
- **データマート**: `GET/DELETE/POST /api/datamart/*`
- **イベント管理**: `GET/POST/PATCH/DELETE /api/events/*`
- **イベントタイプ**: `GET/POST/PATCH/DELETE /api/event-types/*`
- **ヒートマップ**: `GET /api/heatmap/data`, `GET /api/heatmap/holes`, `GET/PUT/POST/DELETE /api/heatmap/layouts/:hole/:floor`（レイアウトはGCSのみ、マルチフロア対応。エディタは `?perf=true` で計測モード有効）
- **ヘルスチェック**: `GET /health`

## インフラストラクチャ

### 実行環境
- **Dockerのみ**: `make build` → `make run-docker`（ローカル直接実行は非推奨）
- クラウド: Google Cloud Run

### 環境変数
- `NODE_ENV`: 実行環境
- `PORT`: サーバーポート（デフォルト: `8080`）
- `SQLITE_DB_PATH`: SQLiteデータベースパス
- `GOOGLE_CLOUD_PROJECT`: GCPプロジェクトID
- `GOOGLE_APPLICATION_CREDENTIALS`: 認証情報パス
- `BQ_DATASET_ID`: BigQueryデータセットID（デフォルト: `scraped_data`）
- `ENABLE_SCHEDULER`: スケジューラーの有効化
- `READONLY_MODE`: 読み取り専用モード（Cloud Run用、`true` で書き込みAPI無効化）

## スキーマ管理

- スキーマは `sql/raw_data/schema.js` で一元管理（Single Source of Truth）
- SQLiteとBigQuery両方のスキーマを生成
- マイグレーションは `sql/*/migrations/` に配置（SQLite用 `.sqlite.sql` / BigQuery用 `.bq.sql`）

## 設定ファイル一覧

| ファイル | 内容 |
|---------|------|
| `src/config/constants.js` | 定数定義 |
| `src/config/slorepo-config.js` | 店舗設定 |
| `src/config/heatmap-layouts/storage.js` | ヒートマップレイアウト管理 |
| `sql/raw_data/schema.js` | 生データスキーマ（Single Source of Truth） |
| `sql/scrape_failures/schema.js` | 失敗記録スキーマ |
| `sql/manual_corrections/schema.js` | 手動補正スキーマ |
| `sql/events/schema.js` | イベントスキーマ（SQLite/BigQuery両対応） |
| `sql/event_types/schema.js` | イベントタイプスキーマ（SQLiteのみ） |
| `sql/datamart/machine_stats/query.sql` | データマート生成クエリ |
| `sql/datamart/machine_stats/create_table.sql` | データマートテーブル定義 |
| `sql/machine_summary/machine_summary.sql` | 機種サマリークエリ |
| `sql/heatmap/heatmap_query.sql` | ヒートマップデータクエリ |

## 変更時の注意

- **スキーマ変更** → マイグレーションファイル作成（`sql/*/migrations/`）
- **新機能追加** → `README.md` と本ドキュメントを更新
- **SQL変更** → `sql/AGENTS.md` を参照
- **店舗追加** → `src/config/slorepo-config.js` を編集

## 参照ドキュメント

| ドキュメント | 内容 |
|-------------|------|
| [README.md](README.md) | プロジェクト詳細・API仕様・機能一覧 |
| [sql/AGENTS.md](sql/AGENTS.md) | SQL開発ガイドライン |
| [deploy/README.md](deploy/README.md) | デプロイ手順 |
