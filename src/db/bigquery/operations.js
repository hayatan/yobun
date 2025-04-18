import util from '../../util/common.js';

const ensureTableExists = async (bigquery, datasetId, tableId) => {
    const dataset = bigquery.dataset(datasetId);
    const table = dataset.table(tableId);
    try {
        const [exists] = await table.exists();
        if (!exists) {
            console.log(`テーブル ${tableId} が存在しません。作成します...`);
            await table.create({
                schema: [
                    { name: 'id', type: 'STRING' }, // IDカラムを追加
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
                    { name: 'timestamp', type: 'TIMESTAMP' }, // タイムスタンプカラムを追加
                ],
            });
            await new Promise(resolve => setTimeout(resolve, 3000));
            console.log(`テーブル ${tableId} を作成しました。`);
        }
    } catch (error) {
        console.error(`テーブル ${tableId} の作成中にエラーが発生しました:`, error);
        throw error;
    }

    for (let i = 0; i < 10; i++) {
        try {
            await table.getMetadata();
            return table;
        } catch (error) {
            console.log(`テーブル ${tableId} の利用可能確認中... (${i + 1}/10)`);
            await util.delay(2000);
        }
    }

    throw new Error(`テーブル ${tableId} が20秒以内に利用可能になりませんでした。`);
};

async function insertWithRetry(table, formattedData, tableId) {
    const MAX_RETRIES = 10;
    const BASE_DELAY = 1000; // 1秒
    for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
        try {
            const timestamp = new Date().toISOString(); // 現在のタイムスタンプを取得
            const formattedRows = formattedData.map(row => ({
                id: `${row.date}_${row.hole}_${row.machine_number}`, // IDを生成
                ...row,
                timestamp, // タイムスタンプを追加
            }));
            await table.insert(formattedRows);
        } catch (error) {
            if (attempt === MAX_RETRIES) {
                console.error(`テーブル ${tableId} にデータを挿入中にエラーが発生しました:`, error);
                throw error;
            }
            const delay = BASE_DELAY * Math.pow(2, attempt - 1);
            console.warn(`挿入に失敗しました。${delay}ms 後にリトライします... (試行回数: ${attempt})`, error);
            await new Promise(resolve => setTimeout(resolve, delay));
        }
    }
}

const saveToBigQuery = async (bigquery, datasetId, tableId, data) => {
    const formattedData = util.formatDiffData(data);

    if (!util.validateDiffData(formattedData)) {
        throw new Error(`データが不完全なため、BigQueryへの保存をスキップします: ${tableId}\n${JSON.stringify(formattedData)}`);
    }

    if (formattedData.length === 0) {
        throw new Error(`データが空のため、BigQueryへの保存をスキップします: ${tableId}`);
    }

    const table = await ensureTableExists(bigquery, datasetId, tableId);

    try {
        await insertWithRetry(table, formattedData, tableId);
    } catch (error) {
        throw error;
    }
};

// BigQueryテーブル再作成とデータ保存
const saveToBigQueryReplace = async (bigquery, datasetId, tableId, data) => {
    const dataset = bigquery.dataset(datasetId);
    const table = dataset.table(tableId);
    try {
        // テーブルを削除して再作成
        await table.delete({ ignoreNotFound: true });
        await saveToBigQuery(bigquery, datasetId, tableId, data);
    } catch (error) {
        console.error(`テーブル ${tableId} の再作成中にエラーが発生しました:`, error);
        throw error;
    }
};

const getSavedHoles = async (bigquery, datasetId, tableId) => {
    const dataset = bigquery.dataset(datasetId);
    const table = dataset.table(tableId);
    try {
        const [rows] = await table.query({
            query: `SELECT DISTINCT hole FROM \`${datasetId}.${tableId}\``,
        });
        return rows.map(row => row.hole);
    } catch (error) {
        console.error(`テーブル ${tableId} から店舗一覧の取得中にエラーが発生しました:`, error);
        return [];
    }
};

const getBigQueryRowCount = async (bigquery, datasetId, tableId) => {
    const dataset = bigquery.dataset(datasetId);
    const table = dataset.table(tableId);
    try {
        const [rows] = await table.query({
            query: `SELECT COUNT(*) as count FROM \`${datasetId}.${tableId}\``,
        });
        return rows[0].count;
    } catch (error) {
        console.error(`テーブル ${tableId} の行数取得中にエラーが発生しました:`, error);
        return 0;
    }
};

export {
    saveToBigQuery,
    saveToBigQueryReplace,
    getSavedHoles,
    getBigQueryRowCount,
};