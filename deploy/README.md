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
GitHub (main) → Cloud Run 継続的デプロイ
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

### 3. Cloud Run Serviceの作成

以下のコマンドでサービスを作成：

```bash
gcloud run deploy yobun-viewer \
  --image gcr.io/yobun-450512/yobun-scraper:latest \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars "READONLY_MODE=true,NODE_ENV=production,GOOGLE_CLOUD_PROJECT=yobun-450512" \
  --memory 1Gi \
  --cpu 1 \
  --timeout 60 \
  --min-instances 0 \
  --max-instances 2 \
  --service-account slot-data-scraper@yobun-450512.iam.gserviceaccount.com \
  --project yobun-450512
```

### 4. 継続的デプロイの設定

※ CLIでは設定できないため、コンソールから設定が必要

[Cloud Run](https://console.cloud.google.com/run?project=yobun-450512)にアクセスして設定：

1. 作成したサービス `yobun-viewer` を選択
2. 「継続的デプロイを設定」をクリック
3. 以下を設定：
   - リポジトリプロバイダ: GitHub
   - リポジトリ: `hayatan/yobun`
   - ブランチ: `main`
   - ビルドタイプ: `Dockerfile`
   - ソースの場所: `/Dockerfile`
4. 「保存」をクリック

### 5. サービスの削除

```bash
gcloud run services delete yobun-viewer \
  --region us-central1 \
  --project yobun-450512 \
  --quiet
```

## デプロイ方法

### 自動デプロイ（推奨）

mainブランチにpushすると、Cloud Runの継続的デプロイが自動実行されます：

```bash
git add .
git commit -m "[変更] ○○の修正"
git push origin main
```

Cloud Runが以下を自動実行：
1. Dockerイメージのビルド
2. Cloud Run Serviceへのデプロイ

### 手動デプロイ

```bash
# デプロイスクリプトを使用
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
