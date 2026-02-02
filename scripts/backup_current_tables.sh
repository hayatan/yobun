#!/bin/bash
# 現在の slot_data テーブルを slot_data_backup にコピー

PROJECT="yobun-450512"
SRC_DATASET="slot_data"
DST_DATASET="slot_data_backup"

# テーブル一覧を取得してコピー
tables=$(bq ls ${PROJECT}:${SRC_DATASET} 2>/dev/null | awk 'NR>2 && /^data_/ {print $1}')

for table in $tables; do
    echo "コピー中: ${table}"
    bq cp --force \
        "${PROJECT}:${SRC_DATASET}.${table}" \
        "${PROJECT}:${DST_DATASET}.${table}" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "  成功: ${table}"
    else
        echo "  失敗: ${table}"
    fi
done

echo "バックアップ完了"
