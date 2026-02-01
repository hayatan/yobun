// ============================================================================
// 同期 ルーター
// ============================================================================
// 
// /util/sync - SQLite→BigQuery同期実行（期間指定対応）
// /util/sync/status - 同期状態取得
// ============================================================================

import { Router } from 'express';
import stateManager from '../state-manager.js';
import sqlite from '../../db/sqlite/operations.js';
import { saveToBigQuery } from '../../db/bigquery/operations.js';
import { BIGQUERY } from '../../config/constants.js';

const JOB_TYPE = 'sync';

const createSyncRouter = (bigquery, db) => {
    const router = Router();

    // 同期処理の状態を取得するエンドポイント
    router.get('/status', (req, res) => {
        res.json(stateManager.getState(JOB_TYPE));
    });

    // 同期処理のエンドポイント（期間指定対応）
    router.post('/', async (req, res) => {
        if (stateManager.isRunning(JOB_TYPE)) {
            return res.status(409).json({ 
                error: '同期処理は既に実行中です',
                status: stateManager.getState(JOB_TYPE)
            });
        }

        try {
            const { startDate, endDate } = req.body;
            
            // バリデーション
            if (!startDate || !endDate) {
                return res.status(400).json({
                    error: 'startDate と endDate を指定してください',
                    status: stateManager.getState(JOB_TYPE)
                });
            }

            // 日付形式のバリデーション (YYYY-MM-DD)
            const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
            if (!dateRegex.test(startDate) || !dateRegex.test(endDate)) {
                return res.status(400).json({
                    error: '日付は YYYY-MM-DD 形式で指定してください',
                    status: stateManager.getState(JOB_TYPE)
                });
            }

            // startDate <= endDate のチェック
            if (startDate > endDate) {
                return res.status(400).json({
                    error: 'startDate は endDate 以前の日付を指定してください',
                    status: stateManager.getState(JOB_TYPE)
                });
            }

            stateManager.startJob(JOB_TYPE);
            stateManager.updateProgress(JOB_TYPE, 0, 0, '同期処理を開始します...');

            // 期間内のデータを日付ごとにグループ化して取得
            console.log(`検索する期間: ${startDate} 〜 ${endDate}`);
            const groupedData = await sqlite.getDiffDataRange(db, startDate, endDate);
            
            if (groupedData.length === 0) {
                stateManager.completeJob(JOB_TYPE, '指定された期間のデータが存在しません');
                return res.status(404).json({ 
                    message: '指定された期間のデータが存在しません',
                    status: stateManager.getState(JOB_TYPE)
                });
            }

            const { datasetId } = BIGQUERY;
            const totalDates = groupedData.length;
            let totalRecords = 0;
            const syncedDates = [];

            // 日付ごとに順次同期
            for (let i = 0; i < groupedData.length; i++) {
                const { date, data } = groupedData[i];
                const tableId = `data_${date.replace(/-/g, '')}`;
                
                stateManager.updateProgress(
                    JOB_TYPE, 
                    i, 
                    totalDates, 
                    `[${i + 1}/${totalDates}] ${date} を同期中... (${data.length}件)`
                );

                console.log(`[${i + 1}/${totalDates}] ${date} を同期中... (${data.length}件)`);

                if (data.length > 0) {
                    await saveToBigQuery(bigquery, datasetId, tableId, data, 'slorepo');
                    totalRecords += data.length;
                    syncedDates.push(date);
                }
            }

            const completionMessage = `同期処理が完了しました (${totalDates}日分, ${totalRecords}件)`;
            stateManager.updateProgress(JOB_TYPE, totalDates, totalDates, completionMessage);
            stateManager.completeJob(JOB_TYPE, completionMessage);

            res.status(200).json({ 
                message: '同期処理が完了しました',
                summary: {
                    totalDates,
                    totalRecords,
                    syncedDates
                },
                status: stateManager.getState(JOB_TYPE)
            });
        } catch (error) {
            stateManager.failJob(JOB_TYPE, error.message);
            res.status(500).json({ 
                error: '同期処理中にエラーが発生しました',
                status: stateManager.getState(JOB_TYPE)
            });
        }
    });

    return router;
};

export default createSyncRouter;
