// ============================================================================
// 強制再取得 ルーター
// ============================================================================
// 
// /util/force-rescrape - 強制再取得実行
// /util/force-rescrape/status - 強制再取得状態取得
// ============================================================================

import { Router } from 'express';
import stateManager from '../state-manager.js';
import sqlite from '../../db/sqlite/operations.js';
import { getTable, saveToBigQuery, deleteBigQueryTable } from '../../db/bigquery/operations.js';
import scrapeSlotDataByMachine from '../../services/slorepo/scraper.js';
import config, { findHoleByName } from '../../config/slorepo-config.js';
import { BIGQUERY } from '../../config/constants.js';
import { acquireLock, releaseLock, getLockStatus } from '../../util/lock.js';

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

    // 強制再取得のエンドポイント
    router.post('/', async (req, res) => {
        if (stateManager.isRunning(JOB_TYPE)) {
            return res.status(409).json({ 
                error: '強制再取得は既に実行中です',
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
            const { date, holeName } = req.body;
            
            if (!date || !holeName) {
                await releaseLock(); // ロック解放
                return res.status(400).json({
                    error: '日付とホール名を指定してください',
                    status: stateManager.getState(JOB_TYPE)
                });
            }

            // ホール設定を確認
            const hole = findHoleByName(holeName);
            if (!hole) {
                await releaseLock(); // ロック解放
                return res.status(400).json({
                    error: '指定されたホールが見つかりません',
                    status: stateManager.getState(JOB_TYPE)
                });
            }

            stateManager.startJob(JOB_TYPE);
            stateManager.updateProgress(JOB_TYPE, 0, 5, '強制再取得を開始します...');

            // 非同期で強制再取得を実行
            (async () => {
                const { datasetId } = BIGQUERY;
                const tableId = `data_${date.replace(/-/g, '')}`;

                try {
                    // Step 1: SQLiteからデータを削除
                    stateManager.updateProgress(JOB_TYPE, 1, 5, `[${date}][${holeName}] SQLiteからデータを削除中...`);
                    await sqlite.deleteDiffData(db, date, holeName);

                    // Step 2: BigQueryテーブル全体を削除
                    stateManager.updateProgress(JOB_TYPE, 2, 5, `[${date}] BigQueryテーブル全体を削除中...`);
                    const table = await getTable(bigquery, datasetId, tableId);
                    await deleteBigQueryTable(table);

                    // Step 3: 新しいデータをスクレイピング
                    stateManager.updateProgress(JOB_TYPE, 3, 5, `[${date}][${holeName}] 新しいデータをスクレイピング中...`);
                    const newData = await scrapeSlotDataByMachine(date, hole.code);
                    
                    // Step 4: SQLiteに保存
                    stateManager.updateProgress(JOB_TYPE, 4, 5, `[${date}][${holeName}] SQLiteに新データを保存中...`);
                    await sqlite.saveDiffData(db, newData, SOURCE);

                    // Step 5: SQLite→BigQuery同期（該当日付の全データ）
                    stateManager.updateProgress(JOB_TYPE, 5, 5, `[${date}] SQLite→BigQuery同期中...`);
                    const allDateData = await sqlite.getDiffDataDate(db, date);
                    if (allDateData.length > 0) {
                        const newTable = await getTable(bigquery, datasetId, tableId);
                        await saveToBigQuery(newTable, allDateData, SOURCE);
                    }

                    stateManager.updateProgress(JOB_TYPE, 5, 5, `[${date}][${holeName}] 強制再取得が完了しました`);
                    stateManager.completeJob(JOB_TYPE, `[${date}][${holeName}] 強制再取得が完了しました`);
                } catch (error) {
                    console.error('強制再取得中にエラーが発生しました:', error);
                    stateManager.failJob(JOB_TYPE, error.message);
                } finally {
                    await releaseLock(); // ロック解放
                }
            })();

            res.status(202).json({ 
                message: '強制再取得を開始しました',
                status: stateManager.getState(JOB_TYPE)
            });
        } catch (error) {
            stateManager.failJob(JOB_TYPE, error.message);
            await releaseLock(); // ロック解放
            res.status(500).json({ 
                error: '強制再取得の開始に失敗しました',
                status: stateManager.getState(JOB_TYPE)
            });
        }
    });

    return router;
};

export default createForceRescrapeRouter;
