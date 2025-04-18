import slorepo from './slorepo.js'; // スクレイピング関数
import config from './slorepo-config.js'; // ホールの設定
import util from './util/common.js'; // 日付生成などのユーティリティ
import sqlite from './db/sqlite/operations.js'; // SQLite関連の関数
import { saveToBigQuery, getBigQueryRowCount, getTable } from './db/bigquery/operations.js'; // BigQuery関連の関数

// メイン処理
const scrape = async (bigquery, datasetId, tableIdPrefix, db, startDate, endDate, updateProgress = () => {}) => {
    const dateRange = util.generateDateRange(startDate, endDate);
    console.log(`処理開始: ${dateRange[0]} - ${dateRange[dateRange.length - 1]}`);

    const totalDates = dateRange.length;
    const totalHoles = config.holes.length;
    const totalTasks = totalDates * totalHoles;
    let completedTasks = 0;

    for (const date of dateRange) {
        const tableId = `${tableIdPrefix}${util.formatUrlDate(date)}`;
        let dateTable = await getTable(bigquery, datasetId, tableId);
        for (const hole of config.holes) {
            try {
                if (typeof updateProgress === 'function') {
                    updateProgress(
                        completedTasks,
                        totalTasks,
                        `[${date}][${hole.name}] 処理中...`
                    );
                }

                const exists = await sqlite.isDiffDataExists(db, date, hole.name);
                if (!exists) {
                    const data = await slorepo(date, hole.code);
                    await sqlite.saveDiffData(db, data);
                }

                // BigQueryに保存
                const data = await sqlite.getDiffData(db, date, hole.name);
                if (data.length > 0) {
                    const bigQueryRowCount = await getBigQueryRowCount(dateTable, hole.name);
                    const sqliteRowCount = data.length;
                    console.log(`[${date}][${hole.name}] BigQuery: ${bigQueryRowCount}件 SQLite: ${sqliteRowCount}件`);
                    if (bigQueryRowCount !== sqliteRowCount) {
                        await saveToBigQuery(dateTable, data);
                    }
                }

                completedTasks++;
                if (typeof updateProgress === 'function') {
                    updateProgress(
                        completedTasks,
                        totalTasks,
                        `[${date}][${hole.name}] 完了`
                    );
                }
            } catch (err) {
                console.error(`処理エラー (${date} - ${hole.name}): ${err.message}`);
                if (typeof updateProgress === 'function') {
                    updateProgress(
                        completedTasks,
                        totalTasks,
                        `[${date}][${hole.name}] エラー: ${err.message}`
                    );
                }
                throw err;
            }
        }
    }
};

export default scrape;
