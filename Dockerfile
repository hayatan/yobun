# ベースイメージを軽量なNode.js公式イメージに変更
FROM node:23-slim
ENV SQLITE_DB_PATH=/tmp/db.sqlite \
    LANG=en_US.UTF-8

# ビルド引数
ARG HOST_UID=1000
ENV YOBUNUSER_UID=${HOST_UID}

# 必要なツールのインストール
RUN apt-get update && apt-get install -y \
    sqlite3 \
    curl

# PuppeteerとChromiumに必要な依存関係のインストール
RUN apt-get update && apt-get install -y --no-install-recommends \
    fonts-ipafont-gothic \
    fonts-wqy-zenhei \
    fonts-thai-tlwg \
    fonts-kacst \
    fonts-freefont-ttf \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libcups2 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libx11-xcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    xdg-utils \
    libu2f-udev \
    libxshmfence1 \
    libglu1-mesa \
    chromium \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 既存のユーザーを削除してから新しいユーザーを作成
RUN if getent passwd node >/dev/null; then userdel -r node; fi \
    && groupadd -r yobunuser && useradd -u $YOBUNUSER_UID -rm -g yobunuser -G audio,video yobunuser \
    && mkdir -p /home/yobunuser/Downloads /app \
    && chown -R yobunuser:yobunuser /home/yobunuser \
    && chown -R yobunuser:yobunuser /app

# Litestreamのインストール
RUN curl -L https://github.com/benbjohnson/litestream/releases/download/v0.3.13/litestream-v0.3.13-linux-amd64.tar.gz \
    -o /litestream.tar.gz \
    && tar -xzf /litestream.tar.gz -C /usr/local/bin/ \
    && chmod +x /usr/local/bin/litestream \
    && rm /litestream.tar.gz

# Puppeteerの設定：Chromiumのダウンロードをスキップし、インストール済みのChromiumを使用
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH="/usr/bin/chromium"

# 作業ディレクトリの設定
WORKDIR /app

# アプリケーションコードをコピー
COPY package*.json ./
RUN npm install --production
COPY . .

# Litestreamの設定ファイルを配置
COPY litestream.yml /etc/litestream.yml

# 条件付きで初期DBコピー
RUN test -f /app/data/db.sqlite && cp /app/data/db.sqlite /tmp/db.sqlite || echo "No local DB found, skipping copy" \
    && chown -R yobunuser:yobunuser /tmp/db.sqlite

# 実行スクリプトをコピーして、エントリポイントに
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh \
    && chown -R yobunuser:yobunuser /app

# ユーザーを切り替え
USER yobunuser

# CMDを美しく！✨
CMD ["/app/entrypoint.sh"]