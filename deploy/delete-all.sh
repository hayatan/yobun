#!/bin/bash
# ============================================================================
# 全リソース削除スクリプト（クリーンアップ用）
# ============================================================================

set -e

PROJECT_ID="yobun-450512"
REGION="asia-northeast1"

echo "=================================================="
echo "⚠️  警告: すべてのCloud Run JobsとSchedulerを削除します"
echo "=================================================="
read -p "続行しますか？ (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "キャンセルしました"
    exit 0
fi

echo ""
echo "1. Cloud Schedulerジョブを削除中..."

# 優先店舗スケジュール
for minute in 0 10 20 30 40 50; do
    gcloud scheduler jobs delete yobun-priority-07${minute} \
      --project ${PROJECT_ID} \
      --location ${REGION} \
      --quiet 2>/dev/null || echo "  - yobun-priority-07${minute} (存在しません)"
done

gcloud scheduler jobs delete yobun-priority-0800 \
  --project ${PROJECT_ID} \
  --location ${REGION} \
  --quiet 2>/dev/null || echo "  - yobun-priority-0800 (存在しません)"

# 通常店舗スケジュール
gcloud scheduler jobs delete yobun-normal-0830 \
  --project ${PROJECT_ID} \
  --location ${REGION} \
  --quiet 2>/dev/null || echo "  - yobun-normal-0830 (存在しません)"

gcloud scheduler jobs delete yobun-normal-1000 \
  --project ${PROJECT_ID} \
  --location ${REGION} \
  --quiet 2>/dev/null || echo "  - yobun-normal-1000 (存在しません)"

gcloud scheduler jobs delete yobun-normal-1230 \
  --project ${PROJECT_ID} \
  --location ${REGION} \
  --quiet 2>/dev/null || echo "  - yobun-normal-1230 (存在しません)"

echo "✓ Cloud Schedulerジョブを削除しました"

echo ""
echo "2. Cloud Run Jobsを削除中..."

gcloud run jobs delete yobun-priority-job \
  --project ${PROJECT_ID} \
  --region ${REGION} \
  --quiet 2>/dev/null || echo "  - yobun-priority-job (存在しません)"

gcloud run jobs delete yobun-normal-job \
  --project ${PROJECT_ID} \
  --region ${REGION} \
  --quiet 2>/dev/null || echo "  - yobun-normal-job (存在しません)"

echo "✓ Cloud Run Jobsを削除しました"

echo ""
echo "=================================================="
echo "クリーンアップが完了しました"
echo "=================================================="
