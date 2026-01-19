# デプロイガイド

Cloud Run JobsとCloud Schedulerを使用した自動スクレイピングシステムのデプロイ手順

## 前提条件

- Google Cloud SDK (`gcloud`) インストール済み
- プロジェクト `yobun-450512` に認証済み
- サービスアカウント `slot-data-scraper@yobun-450512.iam.gserviceaccount.com` 作成済み

## 初回セットアップ

### 1. APIと権限の設定

```bash
# Cloud Scheduler API有効化
gcloud services enable cloudscheduler.googleapis.com --project yobun-450512

# サービスアカウントに権限付与
gcloud projects add-iam-policy-binding yobun-450512 \
  --member="serviceAccount:slot-data-scraper@yobun-450512.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor" \
  --condition=None

gcloud projects add-iam-policy-binding yobun-450512 \
  --member="serviceAccount:slot-data-scraper@yobun-450512.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser" \
  --condition=None

gcloud projects add-iam-policy-binding yobun-450512 \
  --member="serviceAccount:slot-data-scraper@yobun-450512.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin" \
  --condition=None
```

### 2. Cloud Buildトリガーの設定

**方法A: コンソールから設定（推奨）**

1. [Cloud Build > トリガー](https://console.cloud.google.com/cloud-build/triggers?project=yobun-450512)にアクセス
2. 「トリガーを作成」をクリック
3. 以下を設定：
   - 名前: `yobun-main-push`
   - リージョン: `us-central1`
   - イベント: `ブランチにpush`
   - ソース: `hayatan/yobun` (GitHub接続: hayatan)
   - ブランチ: `^main$`
   - 構成: `Cloud Build 構成ファイル (yaml または json)`
   - 場所: `リポジトリ`
   - ファイルの場所: `/cloudbuild.yaml`
4. 「作成」をクリック

**方法B: 手動ビルド**

```bash
gcloud builds submit --config cloudbuild.yaml --project yobun-450512
```

### 3. Cloud Run Jobsの作成

```bash
./deploy/create-jobs.sh
```

このスクリプトは2つのJobを作成します：
- `yobun-priority-job`: 優先店舗用（短時間、10分おきリトライ）
- `yobun-normal-job`: 通常店舗用（全店舗、長めタイムアウト）

### 4. Cloud Schedulerの設定

```bash
./deploy/create-schedules.sh
```

以下のスケジュールが設定されます：
- **優先店舗**: 7:00-8:00 JST（10分おき、7回）
- **通常店舗**: 8:30, 10:00, 12:30 JST（3回）

## コード更新時の手順

```bash
# 1. コードを変更してpush
git add .
git commit -m "[変更] ○○の修正"
git push origin main

# 2. Cloud Buildが自動実行される（トリガー設定済みの場合）
#    または手動ビルド:
#    gcloud builds submit --config cloudbuild.yaml --project yobun-450512

# 3. Cloud Run Jobsのイメージを更新
./deploy/update-jobs.sh
```

## 管理コマンド

### イメージ更新

```bash
./deploy/update-jobs.sh
```

### 全リソース削除

```bash
./deploy/delete-all.sh
```

## ファイル一覧

| ファイル | 用途 |
|---------|------|
| `create-jobs.sh` | Cloud Run Jobs作成 |
| `create-schedules.sh` | Cloud Scheduler設定 |
| `update-jobs.sh` | イメージ更新 |
| `delete-all.sh` | 全リソース削除 |

## 実行スケジュール

| Job | 実行時刻（JST） | 説明 |
|-----|----------------|------|
| 優先店舗 | 7:00-8:00（10分おき） | データ更新が遅い店舗を集中的にチェック |
| 通常店舗 | 8:30, 10:00, 12:30 | 全店舗の未取得データをチェック |

## アーキテクチャ

```
GitHub (main) 
    ↓ push
Cloud Build (自動トリガー)
    ↓ ビルド
Container Registry (gcr.io/yobun-450512/yobun-scraper:latest)
    ↓ 使用
Cloud Run Jobs (yobun-priority-job, yobun-normal-job)
    ↓ 定期実行
Cloud Scheduler
```

## 注意事項

- リージョン: `us-central1` を使用
- GCSロックにより同時実行は防止されます（タイムアウト: 6時間）
- SQLiteデータベースはLitestreamでGCSにバックアップ
- 推定費用: 月額 $0.10以下（無料枠内）
