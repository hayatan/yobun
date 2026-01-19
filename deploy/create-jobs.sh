#!/bin/bash
# ============================================================================
# Cloud Run Jobs 作成スクリプト
# ============================================================================

set -e

PROJECT_ID="yobun-450512"
REGION="us-central1"
IMAGE="gcr.io/${PROJECT_ID}/yobun-scraper:latest"
SERVICE_ACCOUNT="slot-data-scraper@yobun-450512.iam.gserviceaccount.com"

echo "=================================================="
echo "Cloud Run Jobs を作成します"
echo "=================================================="
echo "プロジェクト: ${PROJECT_ID}"
echo "リージョン: ${REGION}"
echo "イメージ: ${IMAGE}"
echo "=================================================="

# 優先店舗用Job（短時間で終了、10分おきにリトライ）
echo ""
echo "1. 優先店舗用Job (yobun-priority-job) を作成中..."
gcloud run jobs create yobun-priority-job \
  --project ${PROJECT_ID} \
  --region ${REGION} \
  --image ${IMAGE} \
  --service-account ${SERVICE_ACCOUNT} \
  --set-env-vars "JOB_MODE=priority,NODE_ENV=production" \
  --memory 2Gi \
  --cpu 1 \
  --task-timeout 600 \
  --max-retries 0

echo "✓ 優先店舗用Job を作成しました"

# 通常店舗用Job（全店舗対象、長めのタイムアウト）
echo ""
echo "2. 通常店舗用Job (yobun-normal-job) を作成中..."
gcloud run jobs create yobun-normal-job \
  --project ${PROJECT_ID} \
  --region ${REGION} \
  --image ${IMAGE} \
  --service-account ${SERVICE_ACCOUNT} \
  --set-env-vars "JOB_MODE=normal,NODE_ENV=production" \
  --memory 2Gi \
  --cpu 1 \
  --task-timeout 3600 \
  --max-retries 0

echo "✓ 通常店舗用Job を作成しました"

echo ""
echo "=================================================="
echo "Cloud Run Jobs の作成が完了しました"
echo "=================================================="
echo ""
echo "次のステップ: ./deploy/create-schedules.sh を実行してスケジュールを設定"
