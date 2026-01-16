#!/bin/sh

set -e

DB_PATH="${SQLITE_DB_PATH:-/tmp/db.sqlite}"
JOB_MODE="${JOB_MODE:-}"

echo "💡 Litestream DBチェック: $DB_PATH"
echo "📋 実行モード: ${JOB_MODE:-Webサーバー（ローカル開発）}"

# DBファイルの復元（存在しない場合のみ）
if [ ! -f "$DB_PATH" ] || [ ! -s "$DB_PATH" ]; then
  echo "🔁 GCSレプリカから復元を試みます..."
  litestream restore -if-replica-exists "$DB_PATH"
else
  echo "✅ 既存のDBファイルが見つかりました。復元スキップ。"
fi

# JOB_MODEが設定されている場合はjob.js、それ以外はserver.js（ローカル開発用）
if [ -n "$JOB_MODE" ]; then
  echo "🚀 Litestreamでレプリケーション＋Job実行"
  exec litestream replicate --exec "node /app/job.js"
else
  echo "🚀 Litestreamでレプリケーション＋Webサーバー起動（ローカル開発）"
  exec litestream replicate --exec "node /app/server.js"
fi
