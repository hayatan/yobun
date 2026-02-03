#!/bin/bash

# Cloud Run Service（読み取り専用）をデプロイするスクリプト
#
# 使用方法:
#   ./deploy/deploy-service.sh
#
# 前提条件:
#   - gcloud CLIがインストール済み
#   - yobun-450512プロジェクトに認証済み
#   - Container Registryにイメージがプッシュ済み

set -e

PROJECT_ID="yobun-450512"
REGION="us-central1"
SERVICE_NAME="yobun-viewer"
IMAGE="gcr.io/${PROJECT_ID}/yobun-scraper:latest"
SERVICE_ACCOUNT="slot-data-scraper@${PROJECT_ID}.iam.gserviceaccount.com"

echo "=========================================="
echo "Cloud Run Service デプロイ"
echo "=========================================="
echo "  プロジェクト: ${PROJECT_ID}"
echo "  リージョン: ${REGION}"
echo "  サービス名: ${SERVICE_NAME}"
echo "  イメージ: ${IMAGE}"
echo "=========================================="

gcloud run deploy ${SERVICE_NAME} \
  --image ${IMAGE} \
  --region ${REGION} \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars "READONLY_MODE=true,NODE_ENV=production,GOOGLE_CLOUD_PROJECT=${PROJECT_ID}" \
  --memory 2Gi \
  --cpu 1 \
  --timeout 60 \
  --service-account ${SERVICE_ACCOUNT} \
  --project ${PROJECT_ID}

echo ""
echo "=========================================="
echo "デプロイ完了"
echo "=========================================="

# デプロイしたサービスのURLを取得して表示
SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
  --region ${REGION} \
  --project ${PROJECT_ID} \
  --format='value(status.url)')

echo "  サービスURL: ${SERVICE_URL}"
echo "=========================================="
