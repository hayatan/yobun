#!/bin/bash
# ============================================================================
# Cloud Build トリガー設定スクリプト
# ============================================================================
# Container Registry へのイメージプッシュのみを行うトリガーを作成
# （Cloud Run サービスへのデプロイは行わない）
# ============================================================================

set -e

PROJECT_ID="yobun-450512"
REGION="us-central1"
REPO_NAME="hayatan/yobun"  # GitHub リポジトリ名（変更してください）

echo "=================================================="
echo "Cloud Build トリガーを設定します"
echo "=================================================="
echo "プロジェクト: ${PROJECT_ID}"
echo "リポジトリ: ${REPO_NAME}"
echo "=================================================="

# 既存の古いトリガーを削除（オプション）
read -p "既存のCloud Runサービスデプロイトリガーを削除しますか？ (y/N): " confirm
if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    echo ""
    echo "既存トリガーを削除中..."
    EXISTING_TRIGGER=$(gcloud builds triggers list --project ${PROJECT_ID} --filter="name~yobun" --format="value(name)" | head -1)
    if [ -n "$EXISTING_TRIGGER" ]; then
        gcloud builds triggers delete "$EXISTING_TRIGGER" --project ${PROJECT_ID} --quiet
        echo "✓ 既存トリガーを削除しました"
    else
        echo "削除するトリガーが見つかりませんでした"
    fi
fi

# 新しいトリガーを作成
echo ""
echo "新しいトリガーを作成中..."
gcloud builds triggers create github \
  --project ${PROJECT_ID} \
  --name "yobun-scraper-build" \
  --repo-name "${REPO_NAME}" \
  --repo-owner "hayatan" \
  --branch-pattern "^main$" \
  --build-config "cloudbuild.yaml" \
  --description "Build and push yobun-scraper image to Container Registry"

echo "✓ 新しいトリガーを作成しました"

echo ""
echo "=================================================="
echo "Cloud Build トリガーの設定が完了しました"
echo "=================================================="
echo ""
echo "次のステップ:"
echo "1. cloudbuild.yaml をリポジトリにコミット&プッシュ"
echo "2. main ブランチへのプッシュで自動ビルドが開始されます"
echo ""
echo "または、手動でビルドを実行:"
echo "  gcloud builds submit --config cloudbuild.yaml --project ${PROJECT_ID}"
