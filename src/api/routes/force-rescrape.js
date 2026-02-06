// ============================================================================
// 再取得 ルーター
// ============================================================================
// 
// POST /util/force-rescrape - 再取得実行（日付範囲対応）
// GET /util/force-rescrape/status - 再取得状態取得
// ============================================================================

import { Router } from 'express';
import stateManager from '../state-manager.js';
import sqlite from '../../db/sqlite/operations.js';
import corrections from '../../db/sqlite/corrections.js';
import failures from '../../db/sqlite/failures.js';
import { saveToBigQuery, deleteBigQueryTable, ensureTableExists } from '../../db/bigquery/operations.js';
import scrapeSlotDataByMachine, { scrapeMachineList, classifyError } from '../../services/slorepo/scraper.js';
import config, { findHoleByName, getHoles, getHolesSortedByPriority } from '../../config/slorepo-config.js';
import { SLOREPO_SOURCE } from '../../config/sources/slorepo.js';
import { BIGQUERY } from '../../config/constants.js';
import { acquireLock, releaseLock, getLockStatus } from '../../util/lock.js';
import { generateDateRange } from '../../util/date.js';

const JOB_TYPE = 'forceRescrape';
const SOURCE = 'slorepo';

const createForceRescrapeRouter = (bigquery, db) => {
    const router = Router();

    // 再取得の状態を取得するエンドポイント
    router.get('/status', async (req, res) => {
        const lockStatus = await getLockStatus();
        res.json({
            ...stateManager.getState(JOB_TYPE),
            lock: lockStatus,
        });
    });

    // 再取得のエンドポイント（日付範囲対応）
    router.post('/', async (req, res) => {
        if (stateManager.isRunning(JOB_TYPE)) {
            return res.status(409).json({ 
                error: '再取得は既に実行中です',
                status: stateManager.getState(JOB_TYPE)
            });
        }

        // GCSロックを確認・取得
        const lockAcquired = await acquireLock();
        if (!lockAcquired) {
            const lockStatus = await getLockStatus();
            return res.status(409).json({
                error: '別のプロセスがスクレイピングを実行中です',
                lock: lockStatus,
                status: stateManager.getState(JOB_TYPE)
            });
        }

        try {
            // 新形式: startDate, endDate, hole
            // 旧形式との互換性: date, holeName
            const { startDate, endDate, hole, date, holeName } = req.body;
            
            // 旧形式の場合は変換
            const actualStartDate = startDate || date;
            const actualEndDate = endDate || date;
            const actualHole = hole || holeName || null; // nullは全店舗
            
            if (!actualStartDate || !actualEndDate) {
                await releaseLock();
                return res.status(400).json({
                    error: '開始日と終了日を指定してください',
                    status: stateManager.getState(JOB_TYPE)
                });
            }

            // 店舗リストを取得
            let holes;
            if (actualHole) {
                const hole = findHoleByName(actualHole);
                if (!hole) {
                    await releaseLock();
                    return res.status(400).json({
                        error: '指定されたホールが見つかりません',
                        status: stateManager.getState(JOB_TYPE)
                    });
                }
                holes = [hole];
            } else {
                holes = getHolesSortedByPriority();
            }

            // 日付範囲を生成
            const dateRange = generateDateRange(new Date(actualStartDate), new Date(actualEndDate));
            const totalTasks = dateRange.length * holes.length;

            stateManager.startJob(JOB_TYPE);
            stateManager.updateProgress(JOB_TYPE, 0, totalTasks, '再取得を開始します...');

            // 非同期で再取得を実行
            (async () => {
                const { datasetId } = BIGQUERY;
                let completedTasks = 0;
                const results = { success: [], failed: [], skipped: [] };

                try {
                    for (const targetDate of dateRange) {
                        const tableId = `data_${targetDate.replace(/-/g, '')}`;
                        
                        for (const targetHole of holes) {
                            completedTasks++;
                            const holeName = targetHole.name;
                            
                            try {
                                stateManager.updateProgress(JOB_TYPE, completedTasks, totalTasks, `[${targetDate}][${holeName}] 処理中...`);

                                // スクレイピング結果を保持
                                let scrapeResult = null;
                                // 失敗時のフォールバック用バックアップ
                                let backupData = [];
                                
                                // 機種数を比較してスキップ判断
                                const savedMachineCount = await sqlite.getMachineCount(db, targetDate, holeName);
                                
                                if (savedMachineCount === 0) {
                                    // 保存済みデータがない場合は新規スクレイピング
                                    console.log(`[${targetDate}][${holeName}] 保存済みデータなし、スクレイピングを実行`);
                                    scrapeResult = await scrapeSlotDataByMachine(targetDate, targetHole.code);
                                    await sqlite.saveDiffData(db, scrapeResult.data, SOURCE);
                                    results.success.push({ date: targetDate, hole: holeName });
                                } else {
                                    // 機種一覧を取得して機種数を比較
                                    const machineList = await scrapeMachineList(targetDate, targetHole.code);
                                    const scrapedMachineCount = machineList.count;
                                    
                                    if (savedMachineCount !== scrapedMachineCount) {
                                        // 機種数が異なる場合: バックアップを取得してからスクレイピング実行
                                        backupData = await sqlite.getDiffData(db, targetDate, holeName);
                                        console.log(`[${targetDate}][${holeName}] 機種数変更: ${savedMachineCount} → ${scrapedMachineCount} (バックアップ: ${backupData.length}件)`);
                                        await sqlite.deleteDiffData(db, targetDate, holeName);
                                        scrapeResult = await scrapeSlotDataByMachine(targetDate, targetHole.code);
                                        await sqlite.saveDiffData(db, scrapeResult.data, SOURCE);
                                        results.success.push({ date: targetDate, hole: holeName });
                                    } else {
                                        // 機種数が同じ場合はスキップ
                                        console.log(`[${targetDate}][${holeName}] 機種数一致: ${savedMachineCount}種 → スキップ`);
                                        results.skipped.push({ date: targetDate, hole: holeName, reason: '機種数一致' });
                                    }
                                }
                                
                                // 機種レベルの失敗処理（バックアップ → 補正データ → 失敗記録の順でフォールバック）
                                if (scrapeResult && scrapeResult.failures && scrapeResult.failures.length > 0) {
                                    console.log(`[${targetDate}][${holeName}] 機種レベルの失敗: ${scrapeResult.failures.length}件`);
                                    for (const machineFailure of scrapeResult.failures) {
                                        try {
                                            // 1. バックアップから該当機種のデータを探す
                                            const backupMachineData = backupData.filter(d => d.machine === machineFailure.machine);
                                            
                                            if (backupMachineData.length > 0) {
                                                // バックアップから復元
                                                await sqlite.saveDiffData(db, backupMachineData, SOURCE);
                                                console.log(`[${targetDate}][${holeName}] 機種: ${machineFailure.machine} - バックアップから復元: ${backupMachineData.length}件`);
                                            } else {
                                                // 2. 補正データを確認（同じデータソースのみ）
                                                const correctionData = await corrections.getMachineCorrections(
                                                    db, targetDate, holeName, machineFailure.machine, SOURCE
                                                );
                                                
                                                if (correctionData.length > 0) {
                                                    // 補正データがあれば利用（失敗として記録しない）
                                                    await corrections.copyToScrapedData(db, targetDate, holeName, machineFailure.machine);
                                                    console.log(`[${targetDate}][${holeName}] 機種: ${machineFailure.machine} - 補正データを利用: ${correctionData.length}件`);
                                                } else {
                                                    // 3. 失敗として記録
                                                    await failures.addFailure(db, {
                                                        date: targetDate,
                                                        hole: holeName,
                                                        holeCode: targetHole.code,
                                                        machine: machineFailure.machine,
                                                        machineUrl: machineFailure.url,
                                                        errorType: machineFailure.errorType,
                                                        errorMessage: machineFailure.message,
                                                    });
                                                    console.log(`[${targetDate}][${holeName}] 機種: ${machineFailure.machine} - 失敗として記録`);
                                                }
                                            }
                                        } catch (failureErr) {
                                            console.error(`機種レベル失敗処理中にエラー: ${failureErr.message}`);
                                        }
                                    }
                                }

                                // BigQueryに同期（Load Job使用、重複防止）
                                const data = await sqlite.getDiffData(db, targetDate, holeName);
                                if (data.length > 0) {
                                    // 新形式: saveToBigQuery(bigquery, datasetId, tableId, data, source)
                                    await saveToBigQuery(bigquery, datasetId, tableId, data, SOURCE);
                                }

                                stateManager.updateProgress(JOB_TYPE, completedTasks, totalTasks, `[${targetDate}][${holeName}] 完了`);
                            } catch (error) {
                                console.error(`[${targetDate}][${holeName}] エラー:`, error.message);
                                
                                // 店舗レベルの失敗: 失敗として記録（データの上書きなし、補正データの利用なし）
                                const errorType = classifyError(error);
                                const machineUrl = SLOREPO_SOURCE.buildUrl.hole(targetHole.code, targetDate);
                                
                                try {
                                    await failures.addFailure(db, {
                                        date: targetDate,
                                        hole: holeName,
                                        holeCode: targetHole.code,
                                        machine: null,
                                        machineUrl,
                                        errorType,
                                        errorMessage: error.message,
                                    });
                                } catch (failureErr) {
                                    console.error(`失敗記録の追加中にエラー: ${failureErr.message}`);
                                }
                                
                                results.failed.push({ date: targetDate, hole: holeName, error: error.message, errorType });
                                stateManager.updateProgress(JOB_TYPE, completedTasks, totalTasks, `[${targetDate}][${holeName}] エラー: ${error.message}`);
                            }
                        }
                    }

                    const summary = `完了: 成功=${results.success.length}, スキップ=${results.skipped.length}, 失敗=${results.failed.length}`;
                    console.log(summary);
                    stateManager.completeJob(JOB_TYPE, summary);
                } catch (error) {
                    console.error('再取得中にエラーが発生しました:', error);
                    stateManager.failJob(JOB_TYPE, error.message);
                } finally {
                    await releaseLock();
                }
            })();

            res.status(202).json({ 
                message: '再取得を開始しました',
                params: {
                    startDate: actualStartDate,
                    endDate: actualEndDate,
                    hole: actualHole || '全店舗',
                    totalTasks,
                },
                status: stateManager.getState(JOB_TYPE)
            });
        } catch (error) {
            stateManager.failJob(JOB_TYPE, error.message);
            await releaseLock();
            res.status(500).json({ 
                error: '再取得の開始に失敗しました',
                status: stateManager.getState(JOB_TYPE)
            });
        }
    });

    return router;
};

export default createForceRescrapeRouter;
