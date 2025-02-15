# ベースイメージ
FROM ubuntu:20.04

# 必要なツールのインストール
RUN apt-get update && apt-get install -y \
    sqlite3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Litestreamのインストール
RUN curl -L https://github.com/benbjohnson/litestream/releases/latest/download/litestream-linux-amd64 \
    -o /usr/local/bin/litestream && \
    chmod +x /usr/local/bin/litestream

# バックエンドアプリケーションのセットアップ
WORKDIR /app
COPY . /app
RUN npm install

# SQLiteデータファイルを保存するディレクトリ
VOLUME /data

# Litestreamの設定ファイル
COPY litestream.yml /etc/litestream.yml

# 実行コマンド（Litestreamとバックエンドを同時起動）
CMD ["litestream", "replicate", "--exec", "node /app/server.js"]
