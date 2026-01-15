#!/bin/bash
# ============================================================================
# Cloud Scheduler 作成スクリプト
# ============================================================================

set -e

PROJECT_ID="yobun-450512"
REGION="asia-northeast1"
SERVICE_ACCOUNT="${PROJECT_ID}@appspot.gserviceaccount.com"

echo "=================================================="
echo "Cloud Scheduler を設定します"
echo "=================================================="
echo "プロジェクト: ${PROJECT_ID}"
echo "リージョン: ${REGION}"
echo "=================================================="

# Cloud Run JobsのURIを取得
PRIORITY_JOB_URI="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/yobun-priority-job:run"
NORMAL_JOB_URI="https://${REGION}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/yobun-normal-job:run"

# ============================================================================
# 優先店舗スケジュール（7:00-8:00 JST、10分おき = 7回）
# ============================================================================
echo ""
echo "1. 優先店舗スケジュールを作成中..."

# 7:00, 7:10, 7:20, 7:30, 7:40, 7:50, 8:00
for minute in 0 10 20 30 40 50; do
    SCHEDULE_NAME="yobun-priority-07${minute}"
    echo "  - ${SCHEDULE_NAME} (7:${minute} JST)"
    
    gcloud scheduler jobs create http ${SCHEDULE_NAME} \
      --project ${PROJECT_ID} \
      --location ${REGION} \
      --schedule "${minute} 7 * * *" \
      --time-zone "Asia/Tokyo" \
      --uri "${PRIORITY_JOB_URI}" \
      --http-method POST \
      --oauth-service-account-email ${SERVICE_ACCOUNT} \
      --description "優先店舗スクレイピング (7:${minute} JST)" \
      --quiet || echo "    (既に存在します)"
done

# 8:00
gcloud scheduler jobs create http yobun-priority-0800 \
  --project ${PROJECT_ID} \
  --location ${REGION} \
  --schedule "0 8 * * *" \
  --time-zone "Asia/Tokyo" \
  --uri "${PRIORITY_JOB_URI}" \
  --http-method POST \
  --oauth-service-account-email ${SERVICE_ACCOUNT} \
  --description "優先店舗スクレイピング (8:00 JST)" \
  --quiet || echo "    (既に存在します)"

echo "✓ 優先店舗スケジュールを作成しました (7回/日)"

# ============================================================================
# 通常店舗スケジュール（8:30, 10:00, 12:30 JST = 3回）
# ============================================================================
echo ""
echo "2. 通常店舗スケジュールを作成中..."

# 8:30
gcloud scheduler jobs create http yobun-normal-0830 \
  --project ${PROJECT_ID} \
  --location ${REGION} \
  --schedule "30 8 * * *" \
  --time-zone "Asia/Tokyo" \
  --uri "${NORMAL_JOB_URI}" \
  --http-method POST \
  --oauth-service-account-email ${SERVICE_ACCOUNT} \
  --description "全店舗スクレイピング (8:30 JST)" \
  --quiet || echo "    (既に存在します)"

# 10:00
gcloud scheduler jobs create http yobun-normal-1000 \
  --project ${PROJECT_ID} \
  --location ${REGION} \
  --schedule "0 10 * * *" \
  --time-zone "Asia/Tokyo" \
  --uri "${NORMAL_JOB_URI}" \
  --http-method POST \
  --oauth-service-account-email ${SERVICE_ACCOUNT} \
  --description "全店舗スクレイピング (10:00 JST)" \
  --quiet || echo "    (既に存在します)"

# 12:30
gcloud scheduler jobs create http yobun-normal-1230 \
  --project ${PROJECT_ID} \
  --location ${REGION} \
  --schedule "30 12 * * *" \
  --time-zone "Asia/Tokyo" \
  --uri "${NORMAL_JOB_URI}" \
  --http-method POST \
  --oauth-service-account-email ${SERVICE_ACCOUNT} \
  --description "全店舗スクレイピング (12:30 JST)" \
  --quiet || echo "    (既に存在します)"

echo "✓ 通常店舗スケジュールを作成しました (3回/日)"

echo ""
echo "=================================================="
echo "Cloud Scheduler の設定が完了しました"
echo "=================================================="
echo ""
echo "スケジュール一覧:"
echo "  優先店舗: 7:00, 7:10, 7:20, 7:30, 7:40, 7:50, 8:00 JST (7回/日)"
echo "  全店舗:   8:30, 10:00, 12:30 JST (3回/日)"
echo ""
echo "確認: gcloud scheduler jobs list --location=${REGION}"
