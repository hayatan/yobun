# ベースイメージを軽量なNode.js公式イメージに変更
FROM node:18-slim

# 必要なツールのインストール
RUN apt-get update && apt-get install -y \
    sqlite3 \
    curl \
    gnupg \
    ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Litestreamのインストール
RUN curl -L https://github.com/benbjohnson/litestream/releases/latest/download/litestream-linux-amd64 \
    -o /usr/local/bin/litestream && \
    chmod +x /usr/local/bin/litestream

# 作業ディレクトリの設定
WORKDIR /app

# アプリケーションコードをコピー
COPY package*.json ./
RUN npm install --production
COPY . .

# SQLiteデータファイルを保存するディレクトリ
VOLUME /data

# Litestreamの設定ファイルを配置
COPY litestream.yml /etc/litestream.yml

# 実行コマンド（Litestreamとバックエンドを同時起動）
CMD ["litestream", "replicate", "--exec", "node /app/server.js"]
