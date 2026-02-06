import scrapeSlotDataByMachine, { scrapeMachineList, classifyError } from './scraper.js';
import config, { getHoles, getHolesSortedByPriority } from '../../config/slorepo-config.js';
import { SLOREPO_SOURCE } from '../../config/sources/slorepo.js';
import { generateDateRange, formatUrlDate } from '../../util/date.js';
import sqlite from '../../db/sqlite/operations.js';
import failures from '../../db/sqlite/failures.js';
import corrections from '../../db/sqlite/corrections.js';
import { saveToBigQuery, getBigQueryRowCount, ensureTableExists } from '../../db/bigquery/operations.js';

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

    const dateRange = generateDateRange(startDate, endDate);
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
        const tableId = `${tableIdPrefix}${formatUrlDate(date)}`;
        // テーブルの存在を確認（なければ作成）
        const dateTable = await ensureTableExists(bigquery, datasetId, tableId);
        
        for (const hole of holes) {
            try {
                if (typeof updateProgress === 'function') {
                    updateProgress(
                        completedTasks,
                        totalTasks,
                        `[${date}][${hole.name}] 処理中...`
                    );
                }

                // スクレイピング結果を保持
                let scrapeResult = null;
                // 失敗時のフォールバック用バックアップ
                let backupData = [];
                
                // 再取得の場合は既存データを削除してスクレイピング
                if (force) {
                    const exists = await sqlite.isDiffDataExists(db, date, hole.name);
                    if (exists) {
                        // バックアップを取得してからデータ削除
                        backupData = await sqlite.getDiffData(db, date, hole.name);
                        console.log(`[${date}][${hole.name}] 再取得モード: 既存データをバックアップ (${backupData.length}件) → 削除`);
                        await sqlite.deleteDiffData(db, date, hole.name);
                    }
                    scrapeResult = await scrapeSlotDataByMachine(date, hole.code);
                    await sqlite.saveDiffData(db, scrapeResult.data, SOURCE);
                } else {
                    // 機種一覧を取得して機種数を比較
                    const savedMachineCount = await sqlite.getMachineCount(db, date, hole.name);
                    
                    if (savedMachineCount === 0) {
                        // 保存済みデータがない場合は新規スクレイピング
                        console.log(`[${date}][${hole.name}] 保存済みデータなし、スクレイピングを実行`);
                        scrapeResult = await scrapeSlotDataByMachine(date, hole.code);
                        await sqlite.saveDiffData(db, scrapeResult.data, SOURCE);
                    } else {
                        // 機種一覧を取得して機種数を比較
                        const machineList = await scrapeMachineList(date, hole.code);
                        const scrapedMachineCount = machineList.count;
                        
                        if (savedMachineCount !== scrapedMachineCount) {
                            // 機種数が異なる場合はスクレイピング実行
                            // バックアップを取得してからデータ削除
                            backupData = await sqlite.getDiffData(db, date, hole.name);
                            console.log(`[${date}][${hole.name}] 機種数が変更: 保存済み=${savedMachineCount}, スクレイピング=${scrapedMachineCount} → バックアップ (${backupData.length}件) → 再取得`);
                            await sqlite.deleteDiffData(db, date, hole.name);
                            scrapeResult = await scrapeSlotDataByMachine(date, hole.code);
                            await sqlite.saveDiffData(db, scrapeResult.data, SOURCE);
                        } else {
                            // 機種数が同じ場合はスキップ
                            console.log(`[${date}][${hole.name}] 機種数一致: ${savedMachineCount}種 → スキップ`);
                            result.skipped.push({ date, hole: hole.name, reason: '機種数一致' });
                        }
                    }
                }
                
                // 機種レベルの失敗処理（バックアップ → 補正データ → 失敗記録の順でフォールバック）
                if (scrapeResult && scrapeResult.failures && scrapeResult.failures.length > 0) {
                    console.log(`[${date}][${hole.name}] 機種レベルの失敗: ${scrapeResult.failures.length}件`);
                    for (const machineFailure of scrapeResult.failures) {
                        try {
                            // 1. バックアップから該当機種のデータを探す
                            const backupMachineData = backupData.filter(d => d.machine === machineFailure.machine);
                            
                            if (backupMachineData.length > 0) {
                                // バックアップから復元
                                await sqlite.saveDiffData(db, backupMachineData, SOURCE);
                                console.log(`[${date}][${hole.name}] 機種: ${machineFailure.machine} - バックアップから復元: ${backupMachineData.length}件`);
                            } else {
                                // 2. 補正データを確認（同じデータソースのみ）
                                const correctionData = await corrections.getMachineCorrections(
                                    db, date, hole.name, machineFailure.machine, SOURCE
                                );
                                
                                if (correctionData.length > 0) {
                                    // 補正データがあれば利用（失敗として記録しない）
                                    await corrections.copyToScrapedData(db, date, hole.name, machineFailure.machine);
                                    console.log(`[${date}][${hole.name}] 機種: ${machineFailure.machine} - 補正データを利用: ${correctionData.length}件`);
                                } else {
                                    // 3. 失敗として記録
                                    await failures.addFailure(db, {
                                        date,
                                        hole: hole.name,
                                        holeCode: hole.code,
                                        machine: machineFailure.machine,
                                        machineUrl: machineFailure.url,
                                        errorType: machineFailure.errorType,
                                        errorMessage: machineFailure.message,
                                    });
                                    console.log(`[${date}][${hole.name}] 機種: ${machineFailure.machine} - 失敗として記録`);
                                }
                            }
                        } catch (failureErr) {
                            console.error(`機種レベル失敗処理中にエラー: ${failureErr.message}`);
                        }
                    }
                }

                // BigQueryに同期（Load Job使用、重複防止）
                const data = await sqlite.getDiffData(db, date, hole.name);
                if (data.length > 0) {
                    const bigQueryRowCount = await getBigQueryRowCount(dateTable, hole.name);
                    const sqliteRowCount = data.length;
                    console.log(`[${date}][${hole.name}] BigQuery: ${bigQueryRowCount}件 SQLite: ${sqliteRowCount}件`);
                    if (bigQueryRowCount !== sqliteRowCount || force) {
                        // 新形式: saveToBigQuery(bigquery, datasetId, tableId, data, source)
                        // 単一店舗データなので、DELETE後にINSERTされる
                        await saveToBigQuery(bigquery, datasetId, tableId, data, SOURCE);
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
                
                // 失敗記録をDBに追加
                const errorType = classifyError(err);
                const machineUrl = SLOREPO_SOURCE.buildUrl.hole(hole.code, date);
                
                try {
                    await failures.addFailure(db, {
                        date,
                        hole: hole.name,
                        holeCode: hole.code,
                        machine: null, // 店舗レベルのエラーの場合は機種不明
                        machineUrl,
                        errorType,
                        errorMessage: err.message,
                    });
                } catch (failureErr) {
                    console.error(`失敗記録の追加中にエラー: ${failureErr.message}`);
                }
                
                completedTasks++;
                result.failed.push({ date, hole: hole.name, error: err.message, errorType });
                
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
