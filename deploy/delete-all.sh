#!/bin/bash
# ============================================================================
# 全リソース削除スクリプト（クリーンアップ用）
# ============================================================================

set -e

PROJECT_ID="yobun-450512"
REGION="us-central1"
SERVICE_NAME="yobun-viewer"

echo "=================================================="
echo "警告: Cloud Run Service を削除します"
echo "=================================================="
echo "  サービス名: ${SERVICE_NAME}"
echo "  リージョン: ${REGION}"
echo "=================================================="
read -p "続行しますか？ (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "キャンセルしました"
    exit 0
fi

echo ""
echo "Cloud Run Service を削除中..."

gcloud run services delete ${SERVICE_NAME} \
  --project ${PROJECT_ID} \
  --region ${REGION} \
  --quiet 2>/dev/null && echo "✓ ${SERVICE_NAME} を削除しました" || echo "  - ${SERVICE_NAME} (存在しません)"

echo ""
echo "=================================================="
echo "クリーンアップが完了しました"
echo "=================================================="
