#!/bin/sh

set -e

DB_PATH="${SQLITE_DB_PATH:-/tmp/db.sqlite}"
JOB_MODE="${JOB_MODE:-}"
READONLY_MODE="${READONLY_MODE:-}"

echo "💡 Litestream DBチェック: $DB_PATH"
echo "📋 実行モード: ${JOB_MODE:-Webサーバー}"
echo "📖 読み取り専用: ${READONLY_MODE:-false}"

# DBファイルの復元（存在しない場合のみ）
if [ ! -f "$DB_PATH" ] || [ ! -s "$DB_PATH" ]; then
  echo "🔁 GCSレプリカから復元を試みます..."
  litestream restore -if-replica-exists "$DB_PATH"
else
  echo "✅ 既存のDBファイルが見つかりました。復元スキップ。"
fi

# 読み取り専用モードの場合はreplicateなしで起動
if [ "$READONLY_MODE" = "true" ]; then
  echo "📖 読み取り専用モードで起動（Litestreamレプリケーションなし）"
  exec node /app/server.js
# JOB_MODEが設定されている場合はjob.js
elif [ -n "$JOB_MODE" ]; then
  echo "🚀 Litestreamでレプリケーション＋Job実行"
  exec litestream replicate --exec "node /app/job.js"
# それ以外はserver.js（管理画面）
else
  echo "🚀 Litestreamでレプリケーション＋Webサーバー起動"
  exec litestream replicate --exec "node /app/server.js"
fi
