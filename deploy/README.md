# デプロイガイド

Cloud Run Serviceを使用した読み取り専用ビューアーのデプロイ手順

## 前提条件

- Google Cloud SDK (`gcloud`) インストール済み
- プロジェクト `yobun-450512` に認証済み
- サービスアカウント `slot-data-scraper@yobun-450512.iam.gserviceaccount.com` 作成済み

## アーキテクチャ

```
ローカルPC (Docker)
├── スクレイピング実行
├── SQLite保存
└── Litestream → GCS バックアップ
         ↓
GitHub (main) → Cloud Build → Container Registry
                                    ↓
                              Cloud Run Service
                              (READONLY_MODE=true)
                                    ↓
                              ユーザーがヒートマップ閲覧
```

- **ローカル**: Dockerでスクレイピング・データ収集を実行
- **Cloud Run Service**: 読み取り専用モードでヒートマップを公開

## 初回セットアップ

### 1. APIの有効化

```bash
# Cloud Run API有効化
gcloud services enable run.googleapis.com --project yobun-450512

# Cloud Build API有効化
gcloud services enable cloudbuild.googleapis.com --project yobun-450512
```

### 2. サービスアカウントの権限設定

```bash
# BigQuery権限
gcloud projects add-iam-policy-binding yobun-450512 \
  --member="serviceAccount:slot-data-scraper@yobun-450512.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer" \
  --condition=None

gcloud projects add-iam-policy-binding yobun-450512 \
  --member="serviceAccount:slot-data-scraper@yobun-450512.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser" \
  --condition=None

# Cloud Storage権限（SQLiteバックアップ読み取り用）
gcloud projects add-iam-policy-binding yobun-450512 \
  --member="serviceAccount:slot-data-scraper@yobun-450512.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer" \
  --condition=None
```

### 3. Cloud Buildトリガーの設定

[Cloud Build > トリガー](https://console.cloud.google.com/cloud-build/triggers?project=yobun-450512)にアクセスして設定：

1. 「トリガーを作成」をクリック
2. 以下を設定：
   - 名前: `yobun-main-push`
   - リージョン: `us-central1`
   - イベント: `ブランチにpush`
   - ソース: `hayatan/yobun` (GitHub接続: hayatan)
   - ブランチ: `^main$`
   - 構成: `Cloud Build 構成ファイル (yaml または json)`
   - 場所: `リポジトリ`
   - ファイルの場所: `/cloudbuild.yaml`
3. 「作成」をクリック

### 4. Cloud Buildサービスアカウントの権限設定

Cloud BuildからCloud Run Serviceをデプロイするために権限が必要：

```bash
# Cloud Buildサービスアカウントを取得
PROJECT_NUMBER=$(gcloud projects describe yobun-450512 --format='value(projectNumber)')
CLOUD_BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

# Cloud Run管理者権限を付与
gcloud projects add-iam-policy-binding yobun-450512 \
  --member="serviceAccount:${CLOUD_BUILD_SA}" \
  --role="roles/run.admin" \
  --condition=None

# サービスアカウントの使用権限を付与
gcloud iam service-accounts add-iam-policy-binding \
  slot-data-scraper@yobun-450512.iam.gserviceaccount.com \
  --member="serviceAccount:${CLOUD_BUILD_SA}" \
  --role="roles/iam.serviceAccountUser" \
  --project=yobun-450512
```

## デプロイ方法

### 自動デプロイ（推奨）

mainブランチにpushすると自動的にビルド・デプロイされます：

```bash
git add .
git commit -m "[変更] ○○の修正"
git push origin main
```

Cloud Buildが以下を自動実行：
1. Dockerイメージのビルド
2. Container Registryへのプッシュ
3. Cloud Run Serviceへのデプロイ

### 手動デプロイ

```bash
# イメージビルド・プッシュ
gcloud builds submit --config cloudbuild.yaml --project yobun-450512

# または、デプロイスクリプトを使用（イメージビルド後）
./deploy/deploy-service.sh
```

## 管理コマンド

### サービスの状態確認

```bash
gcloud run services describe yobun-viewer \
  --region us-central1 \
  --project yobun-450512
```

### ログの確認

```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=yobun-viewer" \
  --project yobun-450512 \
  --limit 50
```

### サービスの削除

```bash
./deploy/delete-all.sh
```

## ファイル一覧

| ファイル | 用途 |
|---------|------|
| `deploy-service.sh` | Cloud Run Service手動デプロイ |
| `delete-all.sh` | Cloud Run Service削除 |

## 環境変数

Cloud Run Serviceに設定される環境変数：

| 変数名 | 値 | 説明 |
|-------|-----|------|
| `READONLY_MODE` | `true` | 読み取り専用モード有効化 |
| `NODE_ENV` | `production` | 本番環境 |
| `GOOGLE_CLOUD_PROJECT` | `yobun-450512` | GCPプロジェクトID |

## 注意事項

- リージョン: `us-central1` を使用
- 読み取り専用モードでは書き込みAPIは403を返します
- SQLiteデータベースはGCSから起動時に復元されます（コールドスタート時）
- アイドル時はインスタンスが0にスケールダウンします（コスト最小化）
