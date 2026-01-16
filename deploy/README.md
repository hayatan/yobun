# デプロイスクリプト

Cloud Run JobsとCloud Schedulerの設定・デプロイ用スクリプト

## 前提条件

- Google Cloud SDK (`gcloud`) がインストール済み
- プロジェクト `yobun-450512` に認証済み
- サービスアカウント `slot-data-scraper-test@yobun-450512.iam.gserviceaccount.com` が作成済み

## デプロイ手順

### 1. Dockerイメージのビルド

**オプションA: 手動ビルド（推奨）**

```bash
# cloudbuild.yamlを使ってビルド＆プッシュ
gcloud builds submit --config cloudbuild.yaml --project yobun-450512
```

**オプションB: 自動ビルド設定**

mainブランチへのpush時に自動ビルドしたい場合：

```bash
# 設定ガイドを表示
./deploy/setup-cloud-build.sh
```

ガイドに従ってCloud Consoleで設定してください。

### 2. Cloud Run Jobsの作成

```bash
# 2つのJobを作成（優先店舗用・通常店舗用）
./deploy/create-jobs.sh
```

### 3. サービスアカウント権限設定

```bash
# 必要な権限を付与
./deploy/setup-permissions.sh
```

このスクリプトは以下の権限を付与します：
- BigQuery Data Editor / Job User
- Storage Object Admin（GCSバックアップ用）
- Cloud Run Invoker（Scheduler起動用）

### 4. Cloud Schedulerの設定

```bash
# 自動実行スケジュールを設定
./deploy/create-schedules.sh
```

### 5. イメージ更新時（コード変更後）

```bash
# 手動でビルド＆プッシュ
gcloud builds submit --config cloudbuild.yaml --project yobun-450512

# Jobのイメージを更新
./deploy/update-jobs.sh
```

**初回デプロイ後の変更フロー**：
1. コード変更
2. `git commit` & `git push`
3. 上記コマンドでイメージをビルド＆更新

## ファイル一覧

| ファイル | 説明 |
|----------|------|
| `setup-cloud-build.sh` | Cloud Build自動ビルドトリガー設定 |
| `setup-permissions.sh` | サービスアカウント権限設定 |
| `create-jobs.sh` | Cloud Run Jobsの作成 |
| `create-schedules.sh` | Cloud Schedulerの設定 |
| `update-jobs.sh` | Cloud Run Jobsの更新（イメージ更新時） |
| `delete-all.sh` | 全リソースの削除（クリーンアップ） |

## 実行スケジュール

| Job | 実行時刻（JST） | 頻度 | 説明 |
|-----|----------------|------|------|
| 優先店舗 | 7:00-8:00 | 10分おき（7回） | データ更新が遅い店舗を優先的にチェック |
| 通常店舗 | 9:00, 12:00 | 1日2回 | 全店舗の未取得データをチェック |

## サービスアカウント

`slot-data-scraper-test@yobun-450512.iam.gserviceaccount.com`

- BigQueryへのデータ書き込み
- GCSへのバックアップ（Litestream）
- Cloud Run Jobsの実行

## 注意事項

- 初回実行前に必ずスクリプトの内容を確認してください
- スケジュールはJSTで設定されています
- リージョン: `us-central1` を使用
- GCSロック機能により、同時実行は防止されます（タイムアウト: 6時間）
- 費用は月額約$0.10以下（無料枠内）です
