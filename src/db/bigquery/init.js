import 'dotenv/config';
import { BigQuery } from '@google-cloud/bigquery';

// プロジェクトIDを環境変数から取得（デフォルト値はフォールバック用）
const projectId = process.env.GOOGLE_CLOUD_PROJECT || 'yobun-450512';

// 環境に応じたBigQueryの設定
const bigquery = process.env.NODE_ENV === 'production'
    ? new BigQuery({ projectId }) // 本番環境ではデフォルト認証を利用
    : new BigQuery({
        projectId,
        keyFilename: process.env.GOOGLE_APPLICATION_CREDENTIALS,
    }); // 開発環境ではキーを直接指定

export default bigquery;