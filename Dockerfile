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
    curl \
    wget \
    gnupg \
    ca-certificates \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libc6 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libgbm1 \
    libgcc1 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libstdc++6 \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    lsb-release \
    xdg-utils \
    # Puppeteerの依存関係
    fonts-ipafont-gothic \
    fonts-wqy-zenhei \
    fonts-thai-tlwg \
    fonts-khmeros \
    fonts-kacst \
    fonts-freefont-ttf \
    dbus \
    dbus-x11 \
    && rm -rf /var/lib/apt/lists/*

# Chromeをインストール
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && \
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google.list && \
    apt-get update && \
    apt-get install -y google-chrome-stable && \
    rm -rf /var/lib/apt/lists/*

# 既存のユーザーを削除してから新しいユーザーを作成
RUN if getent passwd node >/dev/null; then userdel -r node; fi \
    && groupadd -r yobunuser && useradd -u $YOBUNUSER_UID -rm -g yobunuser -G audio,video yobunuser \
    && mkdir -p /home/yobunuser/Downloads \
    && chown -R yobunuser:yobunuser /home/yobunuser

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