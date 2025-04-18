import slorepo from './slorepo.js'; // スクレイピング関数
import config from './slorepo-config.js'; // ホールの設定
import util from './util/common.js'; // 日付生成などのユーティリティ
import sqlite from './db/sqlite/operations.js'; // SQLite関連の関数
import { saveToBigQuery, saveToBigQueryReplace, getBigQueryRowCount } from './db/bigquery/operations.js'; // BigQuery関連の関数

// メイン処理
const scrape = async (bigquery, datasetId, tableIdPrefix, db, startDate, endDate) => {
    const dateRange = util.generateDateRange(startDate, endDate);
    console.log(`処理開始: ${dateRange[0]} - ${dateRange[dateRange.length - 1]}`);

    for (const date of dateRange) {
        for (const hole of config.holes) {
            try {
                const exists = await sqlite.isDiffDataExists(db, date, hole.name);
                if (!exists) {
                    const data = await slorepo(date, hole.code);
                    await sqlite.saveDiffData(db, data);
                }
            } catch (err) {
                console.error(`処理エラー (${date} - ${hole.name}): ${err.message}`);
            }
        }

        // BigQueryに保存
        try {
            const data = await sqlite.getDiffDataDate(db, date); // SQLiteからデータを取得

            if (data.length === 0) {
                console.log(`データが空のため、BigQueryへの保存をスキップします: ${date}`);
                continue;
            }

            const tableId = `${tableIdPrefix}${util.formatUrlDate(date)}`;
            const bigQueryRowCount = await getBigQueryRowCount(bigquery, datasetId, tableId);
            const sqliteRowCount = data.length;

            console.log(`[${date}] BigQueryデータ件数: ${bigQueryRowCount}, SQLiteデータ件数: ${sqliteRowCount}`);

            if (bigQueryRowCount !== sqliteRowCount) {
                await saveToBigQueryReplace(bigquery, datasetId, tableId, data);
                console.log(`BigQueryにデータを保存しました: ${date}`);
            } else {
                console.log(`BigQueryとSQLiteのデータ件数が一致しているため、保存をスキップします: ${date}`);
            }
        } catch (err) {
            console.error(`BigQuery保存エラー (${date}): ${err.message}`);
            console.error(err);
        }
    }
};

export default scrape;
