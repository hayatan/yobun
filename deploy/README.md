# デプロイスクリプト

Cloud Run JobsとCloud Schedulerの設定・デプロイ用スクリプト

## 前提条件

- Google Cloud SDK (`gcloud`) がインストール済み
- プロジェクト `yobun-450512` に認証済み
- Container Registry / Artifact Registry にイメージがプッシュ済み

## デプロイ手順

### 1. Dockerイメージのビルドとプッシュ

```bash
# ローカルでビルド
make build

# Container Registryにタグ付け
docker tag yobun-scraper gcr.io/yobun-450512/yobun-scraper

# プッシュ
docker push gcr.io/yobun-450512/yobun-scraper
```

### 2. Cloud Run Jobsの作成

```bash
# スクリプトを実行
./deploy/create-jobs.sh
```

### 3. Cloud Schedulerの設定

```bash
# スクリプトを実行
./deploy/create-schedules.sh
```

## ファイル一覧

| ファイル | 説明 |
|----------|------|
| `create-jobs.sh` | Cloud Run Jobsの作成 |
| `create-schedules.sh` | Cloud Schedulerの設定 |
| `update-jobs.sh` | Cloud Run Jobsの更新（イメージ更新時） |
| `delete-all.sh` | 全リソースの削除（クリーンアップ） |

## 注意事項

- 初回実行前に必ずスクリプトの内容を確認してください
- スケジュールはJSTで設定されています
- リージョン: `us-central1` を使用
- 費用は月額約$0.10以下（無料枠内）です
