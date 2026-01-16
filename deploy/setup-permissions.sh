#!/bin/bash
# ============================================================================
# サービスアカウント権限設定スクリプト
# ============================================================================

set -e

PROJECT_ID="yobun-450512"
REGION="us-central1"
SERVICE_ACCOUNT="slot-data-scraper-test@yobun-450512.iam.gserviceaccount.com"

echo "=================================================="
echo "サービスアカウント権限を設定します"
echo "=================================================="
echo "サービスアカウント: ${SERVICE_ACCOUNT}"
echo "=================================================="

# ============================================================================
# 1. プロジェクトレベルの権限（既に付与済みだが確認）
# ============================================================================
echo ""
echo "1. プロジェクトレベルの権限を確認・付与..."

REQUIRED_ROLES=(
    "roles/bigquery.dataEditor"
    "roles/bigquery.jobUser"
    "roles/storage.objectAdmin"
)

for role in "${REQUIRED_ROLES[@]}"; do
    echo "  - ${role}"
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SERVICE_ACCOUNT}" \
        --role="${role}" \
        --condition=None \
        --quiet > /dev/null 2>&1 || echo "    (既に付与済み)"
done

echo "✓ プロジェクトレベルの権限設定完了"

# ============================================================================
# 2. Cloud Run Jobs の Invoker 権限
# ============================================================================
echo ""
echo "2. Cloud Run Jobs の Invoker 権限を付与..."

# 優先店舗用Job
echo "  - yobun-priority-job"
gcloud run jobs add-iam-policy-binding yobun-priority-job \
    --project ${PROJECT_ID} \
    --region ${REGION} \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/run.invoker" \
    --quiet 2>&1 || echo "    (Job未作成 or 既に付与済み)"

# 通常店舗用Job
echo "  - yobun-normal-job"
gcloud run jobs add-iam-policy-binding yobun-normal-job \
    --project ${PROJECT_ID} \
    --region ${REGION} \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/run.invoker" \
    --quiet 2>&1 || echo "    (Job未作成 or 既に付与済み)"

echo "✓ Cloud Run Jobs の Invoker 権限設定完了"

echo ""
echo "=================================================="
echo "権限設定が完了しました"
echo "=================================================="
echo ""
echo "次のステップ:"
echo "  1. ./deploy/create-jobs.sh でJobを作成"
echo "  2. ./deploy/setup-permissions.sh を再実行（Invoker権限付与）"
echo "  3. ./deploy/create-schedules.sh でスケジュール設定"
