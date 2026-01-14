import util from '../../util/common.js';
import { BIGQUERY, SCRAPING } from '../../config/constants.js';
import { RAW_DATA_SCHEMA } from '../../../sql/raw_data/schema.js';

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

const insertWithRetry = async (table, formattedData, source = 'slorepo') => {
    const MAX_RETRIES = SCRAPING.insertMaxRetries;
    const BASE_DELAY = SCRAPING.insertBaseDelayMs;
    const BATCH_SIZE = SCRAPING.batchSize;
    
    const timestamp = new Date().toISOString();
    const formattedRows = formattedData.map(row => ({
        id: RAW_DATA_SCHEMA.generateId(row.date, row.hole, row.machine_number, source),
        ...row,
        source,
        timestamp,
    }));
    
    // データをバッチに分割
    const batches = [];
    for (let i = 0; i < formattedRows.length; i += BATCH_SIZE) {
        batches.push(formattedRows.slice(i, i + BATCH_SIZE));
    }

    console.log(`データを ${batches.length} バッチに分割しました。`);

    // 各バッチを順番に処理
    for (let batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        const batch = batches[batchIndex];
        console.log(`バッチ ${batchIndex + 1}/${batches.length} を処理中... (${batch.length}件)`);

        for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
            try {
                // table.insertを使用してデータを挿入
                await table.insert(batch);
                console.log(`バッチ ${batchIndex + 1}/${batches.length} の挿入が完了しました。`);
                break; // 成功したら次のバッチへ
            } catch (error) {
                if (attempt === MAX_RETRIES) {
                    console.error(`バッチ ${batchIndex + 1}/${batches.length} の挿入に失敗しました:`, error.message);
                    throw error;
                }
                const delay = BASE_DELAY * Math.pow(2, attempt - 1);
                console.warn(`バッチ ${batchIndex + 1}/${batches.length} の挿入に失敗しました。${delay}ms 後にリトライします... (試行回数: ${attempt})`, error.message);
                await new Promise(resolve => setTimeout(resolve, delay));
            }
        }
    }
}

const saveToBigQuery = async (table, data, source = 'slorepo') => {
    const tableId = table.id;
    const formattedData = util.formatDiffData(data);

    if (!util.validateDiffData(formattedData)) {
        throw new Error(`データが不完全なため、BigQueryへの保存をスキップします: ${tableId}\n${JSON.stringify(formattedData)}`);
    }

    if (formattedData.length === 0) {
        throw new Error(`データが空のため、BigQueryへの保存をスキップします: ${tableId}`);
    }

    try {
        await insertWithRetry(table, formattedData, source);
    } catch (error) {
        throw error;
    }
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

// BigQueryテーブル全体を削除（強制再取得用）
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
    getSavedHoles,
    getBigQueryRowCount,
    getTable,
    deleteBigQueryTable,
};