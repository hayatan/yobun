# 環境ファイル
ENV_DEV=.env.development
ENV_PROD=.env.production
ENV=.env

# Docker設定
IMAGE_NAME=yobun-scraper
PORT=8080

# ホストのユーザーID
HOST_UID=$(shell id -u)

.PHONY: help run-dev run-server-dev run-docker build clean shell

help:
	@echo "使えるコマンド一覧："
	@echo "  make run-dev      	 	# ローカル実行（litestreamなし）"
	@echo "  make run-server-dev	# ローカルサーバー起動（litestreamなし）"
	@echo "  make build         	# Dockerイメージビルド"
	@echo "  make run-docker    	# Dockerでアプリ起動"
	@echo "  make shell         	# Docker内でシェル起動"
	@echo "  make clean         	# .env削除"

# ローカル開発用
run-dev: $(ENV_DEV)
	cp $(ENV_DEV) $(ENV)
	npm run dev

# ローカル開発用
run-server-dev: $(ENV_DEV)
	cp $(ENV_DEV) $(ENV)
	npm run dev:server

# Dockerビルド
build:
	docker build --build-arg HOST_UID=$(HOST_UID) -t $(IMAGE_NAME) .

# Docker実行
run-docker: $(ENV_PROD)
	cp $(ENV_PROD) $(ENV)
	docker run --env-file .env -v $(PWD)/data:/tmp -p $(PORT):8080 $(IMAGE_NAME)

# Dockerでシェル起動（デバッグ用）
shell:
	docker run -it --env-file .env -v $(PWD)/data:/tmp -w /app $(IMAGE_NAME) /bin/sh

# 片付け
clean:
	rm -f .env
