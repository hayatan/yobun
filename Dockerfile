# ベースイメージを軽量なNode.js公式イメージに変更
FROM node:23-slim
ENV SQLITE_DB_PATH=/tmp/db.sqlite

# 必要なツールのインストール
RUN apt-get update && apt-get install -y \
    sqlite3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Litestreamのインストール
RUN curl -L https://github.com/benbjohnson/litestream/releases/download/v0.3.13/litestream-v0.3.13-linux-amd64.tar.gz \
    -o /litestream.tar.gz \
    && tar -xzf /litestream.tar.gz -C /usr/local/bin/ \
    && chmod +x /usr/local/bin/litestream \
    && rm /litestream.tar.gz

# 作業ディレクトリの設定
WORKDIR /app

# アプリケーションコードをコピー
COPY package*.json ./
RUN npm install --production
COPY . .

# Litestreamの設定ファイルを配置
COPY litestream.yml /etc/litestream.yml

# 条件付きで初期DBコピー
RUN test -f /app/data/db.sqlite && cp /app/data/db.sqlite /tmp/db.sqlite || echo "No local DB found, skipping copy"

# 実行スクリプトをコピーして、エントリポイントに
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# CMDを美しく！✨
CMD ["/app/entrypoint.sh"]