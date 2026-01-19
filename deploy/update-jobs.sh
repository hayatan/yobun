#!/bin/bash
# ============================================================================
# Cloud Run Jobs 更新スクリプト
# イメージ更新時に使用
# ============================================================================

set -e

PROJECT_ID="yobun-450512"
REGION="us-central1"
IMAGE="gcr.io/${PROJECT_ID}/yobun-scraper:latest"
SERVICE_ACCOUNT="slot-data-scraper@yobun-450512.iam.gserviceaccount.com"

echo "=================================================="
echo "Cloud Run Jobs を更新します"
echo "=================================================="
echo "イメージ: ${IMAGE}"
echo "サービスアカウント: ${SERVICE_ACCOUNT}"
echo "=================================================="

# 優先店舗用Job
echo ""
echo "1. 優先店舗用Job (yobun-priority-job) を更新中..."
gcloud run jobs update yobun-priority-job \
  --project ${PROJECT_ID} \
  --region ${REGION} \
  --image ${IMAGE} \
  --service-account ${SERVICE_ACCOUNT}

echo "✓ 優先店舗用Job を更新しました"

# 通常店舗用Job
echo ""
echo "2. 通常店舗用Job (yobun-normal-job) を更新中..."
gcloud run jobs update yobun-normal-job \
  --project ${PROJECT_ID} \
  --region ${REGION} \
  --image ${IMAGE} \
  --service-account ${SERVICE_ACCOUNT}

echo "✓ 通常店舗用Job を更新しました"

echo ""
echo "=================================================="
echo "Cloud Run Jobs の更新が完了しました"
echo "=================================================="
