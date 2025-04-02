#!/bin/sh

set -e

DB_PATH="${SQLITE_DB_PATH:-/tmp/db.sqlite}"

echo "💡 Litestream DBチェック: $DB_PATH"
if [ ! -f "$DB_PATH" ] || [ ! -s "$DB_PATH" ]; then
  echo "🔁 GCSレプリカから復元を試みます..."
  litestream restore -if-replica-exists "$DB_PATH"
else
  echo "✅ 既存のDBファイルが見つかりました。復元スキップ。"
fi

echo "🚀 Litestreamでレプリケーション＋アプリ起動"
exec litestream replicate --exec "node /app/server.js"
