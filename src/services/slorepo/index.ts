import scrapeSlotDataByMachine from './scraper';
import config from '../../config/slorepo-config';
import util from '../../util/common';
import sqlite from '../../db/sqlite/operations';
import { saveToBigQuery, getBigQueryRowCount, getTable } from '../../db/bigquery/operations';
import { BigQuery } from '@google-cloud/bigquery';
import { Database } from 'sqlite3';

type UpdateProgressCallback = (completed: number, total: number, message: string) => void;

// メイン処理
const scrape = async (
    bigquery: BigQuery,
    datasetId: string,
    tableIdPrefix: string,
    db: Database,
    startDate: Date,
    endDate: Date,
    updateProgress: UpdateProgressCallback = () => {}
): Promise<void> => {
    const dateRange = util.generateDateRange(new Date(startDate), new Date(endDate));
    console.log(`処理開始: ${dateRange[0]} - ${dateRange[dateRange.length - 1]}`);

    const totalDates = dateRange.length;
    const totalHoles = config.holes.length;
    const totalTasks = totalDates * totalHoles;
    let completedTasks = 0;

    for (const date of dateRange) {
        const tableId = `${tableIdPrefix}${util.formatUrlDate(new Date(date))}`;
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
                    const data = await scrapeSlotDataByMachine(date, hole.code);
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
                console.error(`処理エラー (${date} - ${hole.name}): ${(err as Error).message}`);
                if (typeof updateProgress === 'function') {
                    updateProgress(
                        completedTasks,
                        totalTasks,
                        `[${date}][${hole.name}] エラー: ${(err as Error).message}`
                    );
                }
                continue;
            }
        }
    }
};

export default scrape; 