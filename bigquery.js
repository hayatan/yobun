require('dotenv').config();
const { BigQuery } = require('@google-cloud/bigquery');

// 環境に応じたBigQueryの設定
const bigquery =  process.env.NODE_ENV === 'production'
        ? new BigQuery() // 本番環境ではデフォルト認証を利用
        : new BigQuery({
            projectId: 'yobun-450512',
            keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS,
        }); // 開発環境ではキーを直接

module.exports = {
    bigquery,
};