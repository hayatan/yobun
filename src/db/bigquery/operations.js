import { Storage } from '@google-cloud/storage';
import util from '../../util/common.js';
import { BIGQUERY, SCRAPING } from '../../config/constants.js';
import { RAW_DATA_SCHEMA } from '../../../sql/raw_data/schema.js';

// GCS設定（一時ファイル用）
const storage = new Storage();
const TEMP_BUCKET = 'youbun-sqlite';  // 既存バケットを再利用

/**
 * テーブルが存在することを確認し、存在しない場合は作成
 * @param {Object} bigquery - BigQueryクライアント
 * @param {string} datasetId - データセットID
 * @param {string} tableId - テーブルID
 * @returns {Promise<Object>} テーブルオブジェクト
 */
const ensureTableExists = async (bigquery, datasetId, tableId) => {
    try {
        const [table] = await bigquery.dataset(datasetId).table(tableId).get();
        return table;
    } catch (error) {
        if (error.code === 404) {
            // テーブルが存在しない場合は作成
            console.log(`テーブル ${tableId} を作成します...`);
            const options = {
                schema: RAW_DATA_SCHEMA.toBigQuerySchema(),
                location: BIGQUERY.location,
            };
            const [table] = await bigquery.dataset(datasetId).createTable(tableId, options);
            console.log(`テーブル ${tableId} を作成しました`);
            return table;
        }
        throw error;
    }
};

/**
 * GCS経由でBigQuery Load Jobを実行
 * 
 * ストリーミングINSERTではなくLoad Jobを使用することで、
 * ストリーミングバッファの問題を回避し、重複を確実に防止する。
 * 
 * @param {Object} table - BigQueryテーブルオブジェクト
 * @param {Array} rows - 挿入するデータ行
 * @param {string} writeDisposition - 書き込みモード (WRITE_APPEND or WRITE_TRUNCATE)
 * @returns {Promise<void>}
 */
const loadViaGcs = async (table, rows, writeDisposition = 'WRITE_APPEND') => {
    const tableId = table.id;
    const tempFileName = `temp/bq_load_${tableId}_${Date.now()}_${Math.random().toString(36).substring(7)}.json`;
    const bucket = storage.bucket(TEMP_BUCKET);
    const file = bucket.file(tempFileName);
    
    // NDJSONにシリアライズしてGCSにアップロード
    const ndjson = rows.map(r => JSON.stringify(r)).join('\n');
    await file.save(ndjson, { contentType: 'application/x-ndjson' });
    
    try {
        // Load Jobでロード（GCSファイルを指定）
        // テーブルは既に作成済みなので、schema.fieldsで明示的に指定
        // v7.x: table.load() はジョブ完了まで待機し、[metadata, apiResponse] を返す
        const [metadata] = await table.load(file, {
            sourceFormat: 'NEWLINE_DELIMITED_JSON',
            writeDisposition: writeDisposition,
            schema: { fields: RAW_DATA_SCHEMA.toBigQuerySchema() },
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
 * データをBigQueryにロード（GCS経由Load Job、重複防止）
 * 
 * データの内容に応じて自動的にモードを選択:
 * - 単一店舗のデータ: その店舗のデータをDELETE後にLoad Job (WRITE_APPEND)
 * - 複数店舗のデータ: Load Job (WRITE_TRUNCATE) でテーブル全体を置換
 * 
 * Load Jobはストリーミングバッファを使用しないため、
 * DML操作が即座に可能で、重複が発生しない。
 * 
 * @param {Object} bigquery - BigQueryクライアント
 * @param {string} datasetId - データセットID
 * @param {string} tableId - テーブルID
 * @param {Array} data - 挿入するデータ
 * @param {string} source - データソース
 * @returns {Promise<number>} 挿入した行数
 */
const loadData = async (bigquery, datasetId, tableId, data, source = 'slorepo') => {
    if (!data || data.length === 0) {
        console.log(`データが空のため、BigQueryへの保存をスキップします: ${tableId}`);
        return 0;
    }

    const projectId = bigquery.projectId;
    const timestamp = new Date().toISOString();
    
    // データを整形
    const formattedData = util.formatDiffData(data);
    if (!util.validateDiffData(formattedData)) {
        throw new Error(`データが不完全なため、BigQueryへの保存をスキップします: ${tableId}`);
    }
    
    const rows = formattedData.map(row => ({
        id: RAW_DATA_SCHEMA.generateId(row.date, row.hole, row.machine_number, source),
        ...row,
        source,
        timestamp,
    }));

    // テーブルの存在を確認（なければ作成）
    await ensureTableExists(bigquery, datasetId, tableId);
    const table = bigquery.dataset(datasetId).table(tableId);

    // データの店舗を確認して、単一店舗か複数店舗かを判定
    const uniqueHoles = [...new Set(rows.map(r => r.hole))];
    
    if (uniqueHoles.length === 1) {
        // 単一店舗: DELETE後にLoad Job (WRITE_APPEND)
        const hole = uniqueHoles[0];
        const date = rows[0].date;
        console.log(`[${tableId}][${hole}] 店舗データを置換モードで同期 (${rows.length}件)`);
        
        // 既存データを削除（Load Jobはストリーミングバッファを使わないため即座に削除可能）
        const deleteQuery = `
            DELETE FROM \`${projectId}.${datasetId}.${tableId}\`
            WHERE date = '${date}' AND hole = '${hole}'
        `;
        try {
            await bigquery.query({ query: deleteQuery });
            console.log(`[${tableId}][${hole}] 既存データを削除しました`);
        } catch (error) {
            // テーブルが空の場合などはエラーを無視
            if (!error.message.includes('Not found')) {
                console.warn(`[${tableId}][${hole}] DELETE中の警告: ${error.message}`);
            }
        }
        
        // GCS経由でLoad Job実行
        await loadViaGcs(table, rows, 'WRITE_APPEND');
        
        console.log(`[${tableId}][${hole}] ${rows.length}件を挿入しました（Load Job）`);
    } else {
        // 複数店舗（日付全体）: Load Job (WRITE_TRUNCATE) でテーブル置換
        console.log(`[${tableId}] テーブル全体を置換モードで同期 (${rows.length}件, ${uniqueHoles.length}店舗)`);
        
        // GCS経由でLoad Job実行（WRITE_TRUNCATEでテーブル全体を置換）
        await loadViaGcs(table, rows, 'WRITE_TRUNCATE');
        
        console.log(`[${tableId}] ${rows.length}件を挿入しました（Load Job TRUNCATE）`);
    }
    
    return rows.length;
};

// ============================================================================
// 以下は既存の関数（後方互換性のため一部残す）
// ============================================================================

const getTable = async (bigquery, datasetId, tableId) => {
    console.error(`テーブル ${datasetId}.${tableId} が存在しない場合は作成します`);
    try {
        // テーブルのスキーマをschema.jsから取得
        const options = {
            schema: RAW_DATA_SCHEMA.toBigQuerySchema(),
            location: BIGQUERY.location,
            description: 'スロットデータの日次テーブル',
            labels: {
                'purpose': 'slot_data',
                'environment': 'production'
            }
        }
    
        // Create a new table in the dataset
        const [table] = await bigquery
            .dataset(datasetId)
            .createTable(tableId, options)

        // テーブルが完全に利用可能になるまで待機
        for (let i = 0; i < SCRAPING.tableWaitRetries; i++) {
            try {
                // メタデータの取得を試みる
                await table.getMetadata();
                
                // 実際にクエリを実行して、テーブルが利用可能か確認
                // プロジェクトIDを含む完全修飾名を使用
                const projectId = bigquery.projectId; // プロジェクトIDを取得
                await table.query({
                    query: `SELECT 1 as dummy FROM \`${projectId}.${datasetId}.${tableId}\` LIMIT 1`,
                    maxResults: 1,
                    useLegacySql: false
                });
                
                // クエリが成功したら、テーブルは利用可能
                console.log(`テーブル ${tableId} が利用可能になりました。`);
                return table;
            } catch (error) {
                console.log(`テーブル ${tableId} の利用可能確認中... (${i + 1}/${SCRAPING.tableWaitRetries})`);
                await util.delay(SCRAPING.tableWaitDelayMs);
            }
        }
        
    } catch (error) {
        if (error.code === 409) {
            console.log(`テーブル ${tableId} は既に存在します。`);
            const [table] = await bigquery
                .dataset(datasetId)
                .table(tableId).get()
            return table;
        }
        console.error(`テーブル ${tableId} の作成中にエラーが発生しました:`, error);
        throw error;
    }
}

/**
 * BigQueryにデータを保存（Load Job使用、重複防止）
 * 
 * 新しい実装: Load Jobを使用し、重複を防止
 * - 単一店舗のデータ: DELETE後にINSERT
 * - 複数店舗のデータ: WRITE_TRUNCATEでテーブル置換
 * 
 * @param {Object} bigqueryOrTable - BigQueryクライアント または テーブルオブジェクト（後方互換性）
 * @param {string|Array} datasetIdOrData - データセットID または データ配列（後方互換性）
 * @param {string} tableIdOrSource - テーブルID または ソース（後方互換性）
 * @param {Array} data - データ配列（新形式のみ）
 * @param {string} source - データソース（新形式のみ）
 * @returns {Promise<number>} 挿入した行数
 */
const saveToBigQuery = async (bigqueryOrTable, datasetIdOrData, tableIdOrSource, data, source = 'slorepo') => {
    // 後方互換性: 旧形式 saveToBigQuery(table, data, source) の判定
    if (bigqueryOrTable && bigqueryOrTable.id && bigqueryOrTable.dataset && Array.isArray(datasetIdOrData)) {
        // 旧形式: saveToBigQuery(table, data, source)
        const table = bigqueryOrTable;
        const oldData = datasetIdOrData;
        const oldSource = tableIdOrSource || 'slorepo';
        
        // テーブルからbigqueryクライアントを取得（大文字Q: bigQuery）
        const bigquery = table.dataset.bigQuery;
        const datasetId = table.dataset.id;
        const tableId = table.id;
        
        return await loadData(bigquery, datasetId, tableId, oldData, oldSource);
    }
    
    // 新形式: saveToBigQuery(bigquery, datasetId, tableId, data, source)
    const bigquery = bigqueryOrTable;
    const datasetId = datasetIdOrData;
    const tableId = tableIdOrSource;
    
    return await loadData(bigquery, datasetId, tableId, data, source);
};

const getSavedHoles = async (table) => {
    try {
        const projectId = table.dataset.projectId;
        const datasetId = table.dataset.id;
        const tableId = table.id;
        const [rows] = await table.query({
            query: `SELECT DISTINCT hole FROM \`${projectId}.${datasetId}.${tableId}\``,
            useLegacySql: false
        });
        return rows.map(row => row.hole);
    } catch (error) {
        console.error(`テーブル ${tableId} から店舗一覧の取得中にエラーが発生しました:`, error);
        return [];
    }
};

const getBigQueryRowCount = async (table, hole) => {
    try {
        const projectId = table.dataset.projectId;
        const datasetId = table.dataset.id;
        const tableId = table.id;
        console.log(`テーブル ${tableId} の行数取得中...`);
        const [rows] = await table.query({
            query: `SELECT COUNT(*) as count FROM (SELECT id FROM \`${projectId}.${datasetId}.${tableId}\` WHERE hole = '${hole}' GROUP BY id)`,
            useLegacySql: false
        });
        return rows[0].count;
    } catch (error) {
        console.error(`テーブル ${tableId} の行数取得中にエラーが発生しました:`, error);
        return 0;
    }
};

// BigQueryテーブル全体を削除（再取得用）
const deleteBigQueryTable = async (table) => {
    try {
        const tableId = table.id;
        console.log(`BigQueryテーブル全体を削除中: ${tableId}`);
        
        await table.delete();
        console.log(`BigQueryテーブル削除完了: ${tableId}`);
        
        return true;
    } catch (error) {
        if (error.code === 404) {
            console.log(`テーブル ${table.id} は存在しませんでした（削除済み）`);
            return true;
        }
        console.error(`BigQueryテーブル削除中にエラーが発生しました: ${error.message}`);
        throw error;
    }
};

export {
    saveToBigQuery,
    loadData,
    ensureTableExists,
    getSavedHoles,
    getBigQueryRowCount,
    getTable,
    deleteBigQueryTable,
};