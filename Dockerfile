# ベースイメージを軽量なNode.js公式イメージに変更
FROM node:23-slim
ENV SQLITE_DB_PATH=/tmp/db.sqlite \
    LANG=en_US.UTF-8

# ビルド引数
ARG HOST_UID=1000
ENV YOBUNUSER_UID=${HOST_UID}

# 必要なツールとPuppeteer/Chromium依存関係を一括インストール
RUN apt-get update && apt-get install -y --no-install-recommends \
    sqlite3 \
    curl \
    ca-certificates \
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

# Node.jsのメモリ制限（1.5GB - Puppeteer/Chromium用に余裕を確保）
ENV NODE_OPTIONS="--max-old-space-size=1536"

# 作業ディレクトリの設定
WORKDIR /app

# 依存関係を先にインストール（キャッシュ効率化）
COPY --chown=yobunuser:yobunuser package*.json ./
RUN npm install --production

# アプリケーションコードをコピー（--chownで所有者設定）
COPY --chown=yobunuser:yobunuser . .

# Litestreamの設定ファイルを配置
COPY --chown=yobunuser:yobunuser litestream.yml /etc/litestream.yml

# 実行スクリプトをコピー
COPY --chown=yobunuser:yobunuser entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# ユーザーを切り替え
USER yobunuser

# CMDを美しく！✨
CMD ["/app/entrypoint.sh"]
