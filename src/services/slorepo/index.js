import scrapeSlotDataByMachine, { scrapeMachineList } from './scraper.js';
import config, { getHoles, getHolesSortedByPriority } from '../../config/slorepo-config.js';
import util from '../../util/common.js';
import sqlite from '../../db/sqlite/operations.js';
import { saveToBigQuery, getBigQueryRowCount, getTable } from '../../db/bigquery/operations.js';

// データソース識別子
const SOURCE = 'slorepo';

/**
 * スクレイピング結果オブジェクト
 * @typedef {Object} ScrapeResult
 * @property {Array<{date: string, hole: string}>} success - 成功した処理
 * @property {Array<{date: string, hole: string, error: string}>} failed - 失敗した処理
 * @property {Array<{date: string, hole: string, reason: string}>} skipped - スキップした処理
 */

/**
 * スクレイピングオプション
 * @typedef {Object} ScrapeOptions
 * @property {boolean} continueOnError - エラー時も処理を継続する（デフォルト: true）
 * @property {boolean} force - 既存データを無視して再取得する（デフォルト: false）
 * @property {string|null} priorityFilter - 優先度フィルタ ('high', 'normal', 'low' または null で全て)
 */

/**
 * メイン処理
 * @param {Object} bigquery - BigQueryクライアント
 * @param {string} datasetId - データセットID
 * @param {string} tableIdPrefix - テーブルIDプレフィックス
 * @param {Object} db - SQLiteデータベース
 * @param {Date} startDate - 開始日
 * @param {Date} endDate - 終了日
 * @param {Function} updateProgress - 進捗更新コールバック
 * @param {ScrapeOptions} options - オプション
 * @returns {Promise<ScrapeResult>} 処理結果
 */
const scrape = async (
    bigquery, 
    datasetId, 
    tableIdPrefix, 
    db, 
    startDate, 
    endDate, 
    updateProgress = () => {},
    options = {}
) => {
    // デフォルトオプション
    const {
        continueOnError = true,
        force = false,
        priorityFilter = null, // 'high', 'normal', 'low' または null（全て）
    } = options;

    const dateRange = util.generateDateRange(startDate, endDate);
    console.log(`処理開始: ${dateRange[0]} - ${dateRange[dateRange.length - 1]}`);
    console.log(`オプション: continueOnError=${continueOnError}, force=${force}, priorityFilter=${priorityFilter}`);

    // 店舗リストを取得（常に優先度順でソート）
    let holes;
    if (priorityFilter) {
        // 特定の優先度のみ
        holes = getHoles({ priority: priorityFilter });
    } else {
        // 全店舗（優先度順）
        holes = getHolesSortedByPriority();
    }
    
    console.log(`対象店舗: ${holes.length}件 (${holes.map(h => h.name).join(', ')})`);

    const totalDates = dateRange.length;
    const totalHoles = holes.length;
    const totalTasks = totalDates * totalHoles;
    let completedTasks = 0;

    // 結果オブジェクト
    const result = {
        success: [],
        failed: [],
        skipped: [],
    };

    for (const date of dateRange) {
        const tableId = `${tableIdPrefix}${util.formatUrlDate(date)}`;
        let dateTable = await getTable(bigquery, datasetId, tableId);
        
        for (const hole of holes) {
            try {
                if (typeof updateProgress === 'function') {
                    updateProgress(
                        completedTasks,
                        totalTasks,
                        `[${date}][${hole.name}] 処理中...`
                    );
                }

                // 強制再取得の場合は既存データを削除してスクレイピング
                if (force) {
                    const exists = await sqlite.isDiffDataExists(db, date, hole.name);
                    if (exists) {
                        console.log(`[${date}][${hole.name}] 強制再取得モード: 既存データを削除`);
                        await sqlite.deleteDiffData(db, date, hole.name);
                    }
                    const data = await scrapeSlotDataByMachine(date, hole.code);
                    await sqlite.saveDiffData(db, data, SOURCE);
                } else {
                    // 機種一覧を取得して機種数を比較
                    const savedMachineCount = await sqlite.getMachineCount(db, date, hole.name);
                    
                    if (savedMachineCount === 0) {
                        // 保存済みデータがない場合は新規スクレイピング
                        console.log(`[${date}][${hole.name}] 保存済みデータなし、スクレイピングを実行`);
                        const data = await scrapeSlotDataByMachine(date, hole.code);
                        await sqlite.saveDiffData(db, data, SOURCE);
                    } else {
                        // 機種一覧を取得して機種数を比較
                        const machineList = await scrapeMachineList(date, hole.code);
                        const scrapedMachineCount = machineList.count;
                        
                        if (savedMachineCount !== scrapedMachineCount) {
                            // 機種数が異なる場合はスクレイピング実行
                            console.log(`[${date}][${hole.name}] 機種数が変更: 保存済み=${savedMachineCount}, スクレイピング=${scrapedMachineCount} → 再取得`);
                            await sqlite.deleteDiffData(db, date, hole.name);
                            const data = await scrapeSlotDataByMachine(date, hole.code);
                            await sqlite.saveDiffData(db, data, SOURCE);
                        } else {
                            // 機種数が同じ場合はスキップ
                            console.log(`[${date}][${hole.name}] 機種数一致: ${savedMachineCount}種 → スキップ`);
                            result.skipped.push({ date, hole: hole.name, reason: '機種数一致' });
                        }
                    }
                }

                // BigQueryに同期
                const data = await sqlite.getDiffData(db, date, hole.name);
                if (data.length > 0) {
                    const bigQueryRowCount = await getBigQueryRowCount(dateTable, hole.name);
                    const sqliteRowCount = data.length;
                    console.log(`[${date}][${hole.name}] BigQuery: ${bigQueryRowCount}件 SQLite: ${sqliteRowCount}件`);
                    if (bigQueryRowCount !== sqliteRowCount || force) {
                        await saveToBigQuery(dateTable, data, SOURCE);
                    }
                }

                completedTasks++;
                result.success.push({ date, hole: hole.name });
                
                if (typeof updateProgress === 'function') {
                    updateProgress(
                        completedTasks,
                        totalTasks,
                        `[${date}][${hole.name}] 完了`
                    );
                }
            } catch (err) {
                console.error(`処理エラー (${date} - ${hole.name}): ${err.message}`);
                
                completedTasks++;
                result.failed.push({ date, hole: hole.name, error: err.message });
                
                if (typeof updateProgress === 'function') {
                    updateProgress(
                        completedTasks,
                        totalTasks,
                        `[${date}][${hole.name}] エラー: ${err.message}`
                    );
                }
                
                // continueOnErrorがfalseの場合はエラーをthrow
                if (!continueOnError) {
                    throw err;
                }
            }
        }
    }

    // 結果サマリーをログ出力
    console.log(`処理完了: 成功=${result.success.length}, 失敗=${result.failed.length}, スキップ=${result.skipped.length}`);
    
    return result;
};

export default scrape;
