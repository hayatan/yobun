# 環境ファイル
ENV_DEV=.env.development
ENV_PROD=.env.production
ENV=.env

# Docker設定
IMAGE_NAME=yobun-scraper
PORT=8080
MEMORY_LIMIT=4g

# ホストのユーザーID
HOST_UID=$(shell id -u)

.PHONY: help build run-docker run-docker-readonly shell clean run-job-priority run-job-normal run-job-all

help:
	@echo "使えるコマンド一覧："
	@echo ""
	@echo "【サーバー起動】"
	@echo "  make build               # Dockerイメージビルド"
	@echo "  make run-docker          # 管理画面として起動（書き込み可）"
	@echo "  make run-docker-readonly # 読み取り専用モードで起動（Cloud Run Service互換）"
	@echo "  make shell               # Docker内でシェル起動"
	@echo ""
	@echo "【ローカルスクレイピング】"
	@echo "  make run-job-priority # 優先店舗のみスクレイピング"
	@echo "  make run-job-normal   # 全店舗の未取得分をスクレイピング"
	@echo "  make run-job-all      # 全店舗強制スクレイピング（テスト用）"
	@echo ""
	@echo "【その他】"
	@echo "  make clean            # .env削除"

# ============================================================================
# ビルド
# ============================================================================

build:
	docker build --build-arg HOST_UID=$(HOST_UID) -t $(IMAGE_NAME) .

# ============================================================================
# サーバー起動（Webフロントエンド）
# ============================================================================

# 管理画面として起動（書き込み可、スケジューラー有効）
run-docker: $(ENV_PROD)
	cp $(ENV_PROD) $(ENV)
	docker run --memory $(MEMORY_LIMIT) --env-file .env -v $(PWD)/data:/tmp -v $(PWD)/credentials:/app/credentials -p $(PORT):8080 $(IMAGE_NAME)

# 読み取り専用モードで起動（Web公開用、書き込みAPIは403）
run-docker-readonly: $(ENV_PROD)
	cp $(ENV_PROD) $(ENV)
	docker run --memory $(MEMORY_LIMIT) --env-file .env -e READONLY_MODE=true -v $(PWD)/data:/tmp -v $(PWD)/credentials:/app/credentials -p $(PORT):8080 $(IMAGE_NAME)

# Dockerでシェル起動（デバッグ用）
shell:
	docker run -it --memory $(MEMORY_LIMIT) --env-file .env -v $(PWD)/data:/tmp -v $(PWD)/credentials:/app/credentials -w /app $(IMAGE_NAME) /bin/sh

# ============================================================================
# ローカルスクレイピング実行
# ============================================================================

# 優先店舗のみ
run-job-priority: $(ENV_PROD)
	cp $(ENV_PROD) $(ENV)
	docker run --memory $(MEMORY_LIMIT) --env-file .env -e JOB_MODE=priority -v $(PWD)/data:/tmp -v $(PWD)/credentials:/app/credentials $(IMAGE_NAME) node job.js

# 全店舗の未取得分
run-job-normal: $(ENV_PROD)
	cp $(ENV_PROD) $(ENV)
	docker run --memory $(MEMORY_LIMIT) --env-file .env -e JOB_MODE=normal -v $(PWD)/data:/tmp -v $(PWD)/credentials:/app/credentials $(IMAGE_NAME) node job.js

# 全店舗強制実行（テスト用）
run-job-all: $(ENV_PROD)
	cp $(ENV_PROD) $(ENV)
	docker run --memory $(MEMORY_LIMIT) --env-file .env -e JOB_MODE=all -v $(PWD)/data:/tmp -v $(PWD)/credentials:/app/credentials $(IMAGE_NAME) node job.js

# ============================================================================
# クリーンアップ
# ============================================================================

clean:
	rm -f .env
