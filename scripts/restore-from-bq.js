// scripts/restore-from-bq.js

require('dotenv').config();
const { bigquery } = require('../bigquery');
const { db } = require('../sqlite');
const { formatDiffData } = require('../src/util/common');
const { saveDiffData, createScrapedDataTableIfNotExists } = require('../src/util/sqlite');

function formatDate(date) {
    const yyyy = date.getFullYear();
    const mm = String(date.getMonth() + 1).padStart(2, '0');
    const dd = String(date.getDate()).padStart(2, '0');
    return `${yyyy}${mm}${dd}`;
}

(async () => {
    try {
        await createScrapedDataTableIfNotExists(db);

        const dataset = 'slot_data';
        const startDate = new Date('2024-09-16');
        const endDate = new Date();

        for (let date = new Date(startDate); date <= endDate; date.setDate(date.getDate() + 1)) {
            const table = `data_${formatDate(date)}`;
            const query = `
                SELECT AS STRUCT *
                FROM (
                    SELECT t.*, ROW_NUMBER() OVER (PARTITION BY t.id ORDER BY t.timestamp DESC) AS rn
                    FROM \`${dataset}.${table}\` t
                    WHERE t.id IS NOT NULL
                )
                WHERE rn = 1
            `;

            console.log(`\nBigQueryからデータ取得中... (${dataset}.${table})`);
            try {
                const [rows] = await bigquery.query({ query });
                console.log(`取得件数: ${rows.length}件`);

                const formatted = formatDiffData(rows);

                console.log(`整形後の件数: ${formatted.length}件`);
                await saveDiffData(db, formatted);
            } catch (queryErr) {
                console.warn(`スキップ: ${table} は存在しないか、クエリで失敗しました。`);
            }
        }

        console.log('\nSQLiteへの全データ保存が完了しました！');
    } catch (err) {
        console.error('復元中にエラーが発生しました:', err);
    } finally {
        db.close();
    }
})();