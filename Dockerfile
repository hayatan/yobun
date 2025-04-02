# ベースイメージを軽量なNode.js公式イメージに変更
FROM node:23-slim

# 必要なツールのインストール
RUN apt-get update && apt-get install -y \
    sqlite3 \
    curl \
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

# 環境変数PORTを設定（デフォルトは8080）
ENV PORT 8080

# 実行コマンド（Litestreamとバックエンドを同時起動）
CMD ["sh", "-c", "litestream replicate --exec \"node /app/server.js\""]
