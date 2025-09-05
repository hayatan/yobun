import util from '../../util/common.js';

const getTable = async (bigquery, datasetId, tableId) => {
    console.error(`テーブル ${datasetId}.${tableId} が存在しない場合は作成します`);
    try {
        // テーブルのスキーマを定義
        const options = {
            schema: [
                { name: 'id', type: 'STRING' },
                { name: 'date', type: 'STRING' },
                { name: 'hole', type: 'STRING' },
                { name: 'machine', type: 'STRING' },
                { name: 'machine_number', type: 'INTEGER' },
                { name: 'diff', type: 'INTEGER' },
                { name: 'game', type: 'INTEGER' },
                { name: 'big', type: 'INTEGER' },
                { name: 'reg', type: 'INTEGER' },
                { name: 'combined_rate', type: 'STRING' },
                { name: 'max_my', type: 'INTEGER' },
                { name: 'max_mdia', type: 'INTEGER' },
                { name: 'win', type: 'INTEGER' },
                { name: 'timestamp', type: 'TIMESTAMP' },
            ],
            location: 'US',
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
        for (let i = 0; i < 15; i++) {
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
                console.log(`テーブル ${tableId} の利用可能確認中... (${i + 1}/15)`);
                await util.delay(3000);
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

const insertWithRetry = async (table, formattedData) => {
    const MAX_RETRIES = 10;
    const BASE_DELAY = 1000; // 1秒
    const BATCH_SIZE = 1000; // バッチサイズを1000件に設定
    
    const timestamp = new Date().toISOString();
    const formattedRows = formattedData.map(row => ({
        id: `${row.date}_${row.hole}_${row.machine_number}`,
        ...row,
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

const saveToBigQuery = async (table, data) => {
    const tableId = table.id;
    const formattedData = util.formatDiffData(data);

    if (!util.validateDiffData(formattedData)) {
        throw new Error(`データが不完全なため、BigQueryへの保存をスキップします: ${tableId}\n${JSON.stringify(formattedData)}`);
    }

    if (formattedData.length === 0) {
        throw new Error(`データが空のため、BigQueryへの保存をスキップします: ${tableId}`);
    }

    try {
        await insertWithRetry(table, formattedData, tableId);
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

// 特定の日付とホールのデータを削除
const deleteBigQueryData = async (table, hole) => {
    try {
        const projectId = table.dataset.projectId;
        const datasetId = table.dataset.id;
        const tableId = table.id;
        
        const query = `
            DELETE FROM \`${projectId}.${datasetId}.${tableId}\`
            WHERE hole = '${hole}'
        `;
        
        console.log(`BigQueryからデータを削除中: ${tableId} - ${hole}`);
        
        // BigQueryクライアントを使用してクエリを実行
        const bigquery = table.dataset.parent;
        const [job] = await bigquery.createQueryJob({
            query,
            useLegacySql: false
        });
        
        // ジョブの完了を待機
        const [rows] = await job.getQueryResults();
        console.log(`BigQueryデータ削除完了: ${tableId} - ${hole}`);
        
        return true;
    } catch (error) {
        console.error(`BigQueryデータ削除中にエラーが発生しました: ${error.message}`);
        throw error;
    }
};

export {
    saveToBigQuery,
    getSavedHoles,
    getBigQueryRowCount,
    getTable,
    deleteBigQueryData,
};