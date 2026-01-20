// ============================================================================
// 再取得 ルーター
// ============================================================================
// 
// POST /util/force-rescrape - 再取得実行（日付範囲、force オプション対応）
// GET /util/force-rescrape/status - 再取得状態取得
// ============================================================================

import { Router } from 'express';
import stateManager from '../state-manager.js';
import sqlite from '../../db/sqlite/operations.js';
import { getTable, saveToBigQuery, deleteBigQueryTable } from '../../db/bigquery/operations.js';
import scrapeSlotDataByMachine, { scrapeMachineList } from '../../services/slorepo/scraper.js';
import config, { findHoleByName, getHoles, getHolesSortedByPriority } from '../../config/slorepo-config.js';
import { BIGQUERY } from '../../config/constants.js';
import { acquireLock, releaseLock, getLockStatus } from '../../util/lock.js';
import util from '../../util/common.js';

const JOB_TYPE = 'forceRescrape';
const SOURCE = 'slorepo';

const createForceRescrapeRouter = (bigquery, db) => {
    const router = Router();

    // 強制再取得の状態を取得するエンドポイント
    router.get('/status', async (req, res) => {
        const lockStatus = await getLockStatus();
        res.json({
            ...stateManager.getState(JOB_TYPE),
            lock: lockStatus,
        });
    });

    // 再取得のエンドポイント（日付範囲、forceオプション対応）
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
            // 新形式: startDate, endDate, hole, force
            // 旧形式との互換性: date, holeName
            const { startDate, endDate, hole, force = false, date, holeName } = req.body;
            
            // 旧形式の場合は変換
            const actualStartDate = startDate || date;
            const actualEndDate = endDate || date;
            const actualHole = hole || holeName || null; // nullは全店舗
            const actualForce = force;
            
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
            const dateRange = util.generateDateRange(new Date(actualStartDate), new Date(actualEndDate));
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

                                if (actualForce) {
                                    // 強制再取得: 既存データを削除して再取得
                                    console.log(`[${targetDate}][${holeName}] 強制再取得モード`);
                                    await sqlite.deleteDiffData(db, targetDate, holeName);
                                    
                                    const newData = await scrapeSlotDataByMachine(targetDate, targetHole.code);
                                    await sqlite.saveDiffData(db, newData, SOURCE);
                                    
                                    results.success.push({ date: targetDate, hole: holeName });
                                } else {
                                    // 通常再取得: 機種数を比較してスキップ判断
                                    const savedMachineCount = await sqlite.getMachineCount(db, targetDate, holeName);
                                    
                                    if (savedMachineCount === 0) {
                                        // 保存済みデータがない場合は新規スクレイピング
                                        console.log(`[${targetDate}][${holeName}] 保存済みデータなし、スクレイピングを実行`);
                                        const newData = await scrapeSlotDataByMachine(targetDate, targetHole.code);
                                        await sqlite.saveDiffData(db, newData, SOURCE);
                                        results.success.push({ date: targetDate, hole: holeName });
                                    } else {
                                        // 機種一覧を取得して機種数を比較
                                        const machineList = await scrapeMachineList(targetDate, targetHole.code);
                                        const scrapedMachineCount = machineList.count;
                                        
                                        if (savedMachineCount !== scrapedMachineCount) {
                                            // 機種数が異なる場合はスクレイピング実行
                                            console.log(`[${targetDate}][${holeName}] 機種数変更: ${savedMachineCount} → ${scrapedMachineCount}`);
                                            await sqlite.deleteDiffData(db, targetDate, holeName);
                                            const newData = await scrapeSlotDataByMachine(targetDate, targetHole.code);
                                            await sqlite.saveDiffData(db, newData, SOURCE);
                                            results.success.push({ date: targetDate, hole: holeName });
                                        } else {
                                            // 機種数が同じ場合はスキップ
                                            console.log(`[${targetDate}][${holeName}] 機種数一致: ${savedMachineCount}種 → スキップ`);
                                            results.skipped.push({ date: targetDate, hole: holeName, reason: '機種数一致' });
                                        }
                                    }
                                }

                                // BigQueryに同期
                                const data = await sqlite.getDiffData(db, targetDate, holeName);
                                if (data.length > 0) {
                                    const table = await getTable(bigquery, datasetId, tableId);
                                    await saveToBigQuery(table, data, SOURCE);
                                }

                                stateManager.updateProgress(JOB_TYPE, completedTasks, totalTasks, `[${targetDate}][${holeName}] 完了`);
                            } catch (error) {
                                console.error(`[${targetDate}][${holeName}] エラー:`, error.message);
                                results.failed.push({ date: targetDate, hole: holeName, error: error.message });
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
                    force: actualForce,
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
