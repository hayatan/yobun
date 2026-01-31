// ============================================================================
// イベント BigQuery操作
// ============================================================================
// 
// events テーブルのBigQuery同期を提供
// SQLiteをプライマリとし、BigQueryに全データを同期
// ============================================================================

import { Storage } from '@google-cloud/storage';
import { EVENTS_SCHEMA } from '../../../sql/events/schema.js';
import { BIGQUERY } from '../../config/constants.js';

// GCS設定（一時ファイル用）
const storage = new Storage();
const TEMP_BUCKET = 'youbun-sqlite';

// BigQueryのデータセットとテーブル
const EVENTS_DATASET = 'slot_data';
const EVENTS_TABLE = 'events';

/**
 * eventsテーブルが存在することを確認し、存在しない場合は作成
 * @param {Object} bigquery - BigQueryクライアント
 * @returns {Promise<Object>} テーブルオブジェクト
 */
const ensureTableExists = async (bigquery) => {
    try {
        const [table] = await bigquery.dataset(EVENTS_DATASET).table(EVENTS_TABLE).get();
        return table;
    } catch (error) {
        if (error.code === 404) {
            // テーブルが存在しない場合は作成
            console.log(`テーブル ${EVENTS_TABLE} を作成します...`);
            const options = {
                schema: EVENTS_SCHEMA.toBigQuerySchema(),
                location: BIGQUERY.location,
                description: 'イベントカレンダー（LINE告知、特定日など）',
            };
            const [table] = await bigquery.dataset(EVENTS_DATASET).createTable(EVENTS_TABLE, options);
            console.log(`テーブル ${EVENTS_TABLE} を作成しました`);
            return table;
        }
        throw error;
    }
};

/**
 * GCS経由でBigQuery Load Jobを実行
 * @param {Object} table - BigQueryテーブルオブジェクト
 * @param {Array} rows - 挿入するデータ行
 * @returns {Promise<void>}
 */
const loadViaGcs = async (table, rows) => {
    const tempFileName = `temp/bq_load_events_${Date.now()}_${Math.random().toString(36).substring(7)}.json`;
    const bucket = storage.bucket(TEMP_BUCKET);
    const file = bucket.file(tempFileName);
    
    // NDJSONにシリアライズしてGCSにアップロード
    const ndjson = rows.map(r => JSON.stringify(r)).join('\n');
    await file.save(ndjson, { contentType: 'application/x-ndjson' });
    
    try {
        // Load Jobでロード（WRITE_TRUNCATEでテーブル全体を置換）
        const [metadata] = await table.load(file, {
            sourceFormat: 'NEWLINE_DELIMITED_JSON',
            writeDisposition: 'WRITE_TRUNCATE',
            schema: { fields: EVENTS_SCHEMA.toBigQuerySchema() },
        });
        
        // エラーチェック
        if (metadata.status && metadata.status.errors && metadata.status.errors.length > 0) {
            throw new Error(`Load Job エラー: ${JSON.stringify(metadata.status.errors)}`);
        }
    } finally {
        // 一時ファイルを削除
        try {
            await file.delete({ ignoreNotFound: true });
        } catch (deleteError) {
            console.warn(`一時ファイル削除中の警告: ${deleteError.message}`);
        }
    }
};

/**
 * SQLiteのイベントデータをBigQueryに同期
 * 全データを WRITE_TRUNCATE で置換
 * 
 * @param {Object} bigquery - BigQueryクライアント
 * @param {Array} events - イベントデータ配列（SQLiteから取得）
 * @returns {Promise<number>} 同期した行数
 */
const syncEvents = async (bigquery, events) => {
    if (!events || events.length === 0) {
        console.log('イベントデータが空のため、BigQueryへの同期をスキップします');
        
        // 空の場合はテーブルを空にする
        try {
            await ensureTableExists(bigquery);
            const table = bigquery.dataset(EVENTS_DATASET).table(EVENTS_TABLE);
            const projectId = bigquery.projectId;
            
            await bigquery.query({
                query: `DELETE FROM \`${projectId}.${EVENTS_DATASET}.${EVENTS_TABLE}\` WHERE TRUE`,
            });
            console.log('BigQuery eventsテーブルを空にしました');
        } catch (error) {
            console.warn(`BigQuery eventsテーブルの削除中の警告: ${error.message}`);
        }
        
        return 0;
    }
    
    // テーブルの存在を確認（なければ作成）
    await ensureTableExists(bigquery);
    const table = bigquery.dataset(EVENTS_DATASET).table(EVENTS_TABLE);
    
    // データを整形（SQLiteのカラム名をそのまま使用）
    const rows = events.map(event => ({
        id: event.id,
        date: event.date,
        hole: event.hole,
        event: event.event,
        description: event.description || null,
        created_at: event.created_at,
        updated_at: event.updated_at,
    }));
    
    console.log(`[events] BigQueryに同期開始 (${rows.length}件)`);
    
    // GCS経由でLoad Job実行（WRITE_TRUNCATEでテーブル全体を置換）
    await loadViaGcs(table, rows);
    
    console.log(`[events] BigQueryに ${rows.length}件 を同期しました`);
    
    return rows.length;
};

/**
 * BigQueryからイベントを取得（確認用）
 * @param {Object} bigquery - BigQueryクライアント
 * @param {object} [filters] - フィルタ条件
 * @returns {Promise<Array>} イベント配列
 */
const getEventsFromBigQuery = async (bigquery, filters = {}) => {
    await ensureTableExists(bigquery);
    
    const projectId = bigquery.projectId;
    let query = `SELECT * FROM \`${projectId}.${EVENTS_DATASET}.${EVENTS_TABLE}\` WHERE 1=1`;
    
    if (filters.startDate) {
        query += ` AND date >= '${filters.startDate}'`;
    }
    
    if (filters.endDate) {
        query += ` AND date <= '${filters.endDate}'`;
    }
    
    if (filters.hole) {
        query += ` AND hole = '${filters.hole}'`;
    }
    
    if (filters.event) {
        query += ` AND event = '${filters.event}'`;
    }
    
    query += ' ORDER BY date DESC';
    
    const [rows] = await bigquery.query({ query });
    return rows;
};

/**
 * BigQueryのイベントテーブルの行数を取得
 * @param {Object} bigquery - BigQueryクライアント
 * @returns {Promise<number>} 行数
 */
const getEventCount = async (bigquery) => {
    try {
        await ensureTableExists(bigquery);
        const projectId = bigquery.projectId;
        
        const [rows] = await bigquery.query({
            query: `SELECT COUNT(*) as count FROM \`${projectId}.${EVENTS_DATASET}.${EVENTS_TABLE}\``,
        });
        
        return rows[0]?.count || 0;
    } catch (error) {
        console.error(`イベント件数取得中にエラー: ${error.message}`);
        return 0;
    }
};

export {
    ensureTableExists,
    syncEvents,
    getEventsFromBigQuery,
    getEventCount,
    EVENTS_DATASET,
    EVENTS_TABLE,
};
