#!/bin/bash
# ============================================================================
# Cloud Build トリガー設定ガイド
# ============================================================================
# Container Registry へのイメージプッシュを自動化するトリガーを作成
# 
# 注意: このスクリプトはGitHubとCloud Buildの連携設定をガイドします。
#       連携はCloud Consoleで行う必要があります。
# ============================================================================

PROJECT_ID="yobun-450512"
REGION="us-central1"
REPO_OWNER="hayatan"
REPO_NAME="yobun"

echo "=================================================="
echo "Cloud Build 自動ビルド設定ガイド"
echo "=================================================="
echo "プロジェクト: ${PROJECT_ID}"
echo "リポジトリ: ${REPO_OWNER}/${REPO_NAME}"
echo "=================================================="
echo ""

# 既存のトリガーを確認
echo "既存のCloud Buildトリガーを確認中..."
EXISTING_TRIGGERS=$(gcloud builds triggers list --project ${PROJECT_ID} --format="table(name,description,createTime)" 2>&1)

if echo "$EXISTING_TRIGGERS" | grep -q "yobun"; then
    echo ""
    echo "✅ 既存のトリガーが見つかりました:"
    echo "$EXISTING_TRIGGERS"
    echo ""
    read -p "既存のトリガーを削除して再作成しますか？ (y/N): " confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        TRIGGER_NAME=$(echo "$EXISTING_TRIGGERS" | grep "yobun" | awk '{print $1}' | head -1)
        gcloud builds triggers delete "$TRIGGER_NAME" --project ${PROJECT_ID} --quiet
        echo "✓ 既存トリガーを削除しました"
    fi
else
    echo "  トリガーは見つかりませんでした。新規作成を行います。"
fi

echo ""
echo "=================================================="
echo "GitHub連携の設定"
echo "=================================================="
echo ""
echo "Cloud BuildでGitHubリポジトリを使用するには、"
echo "Cloud Consoleでの連携設定が必要です。"
echo ""
echo "📋 手順:"
echo ""
echo "1. 以下のURLをブラウザで開く:"
echo "   https://console.cloud.google.com/cloud-build/triggers/connect?project=${PROJECT_ID}"
echo ""
echo "2. 'ソースを選択' で 'GitHub' を選択"
echo ""
echo "3. GitHubアカウントで認証し、リポジトリ '${REPO_OWNER}/${REPO_NAME}' を接続"
echo ""
echo "4. 接続完了後、以下のURLでトリガーを作成:"
echo "   https://console.cloud.google.com/cloud-build/triggers/add?project=${PROJECT_ID}"
echo ""
echo "   - 名前: yobun-scraper-build"
echo "   - リポジトリ: ${REPO_OWNER}/${REPO_NAME}"
echo "   - ブランチ: ^main$"
echo "   - 構成: cloudbuild.yaml"
echo ""
echo "=================================================="
echo ""
echo "⚡ 代替案: 手動ビルド"
echo ""
echo "自動ビルドを設定しない場合は、以下のコマンドで手動ビルドできます："
echo ""
echo "  gcloud builds submit --config cloudbuild.yaml --project ${PROJECT_ID}"
echo ""
echo "=================================================="
