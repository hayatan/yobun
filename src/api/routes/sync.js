// ============================================================================
// 同期 ルーター
// ============================================================================
// 
// /util/sync - SQLite→BigQuery同期実行
// /util/sync/status - 同期状態取得
// ============================================================================

import { Router } from 'express';
import stateManager from '../state-manager.js';
import sqlite from '../../db/sqlite/operations.js';
import { getTable, saveToBigQuery } from '../../db/bigquery/operations.js';
import { BIGQUERY } from '../../config/constants.js';

const JOB_TYPE = 'sync';

const createSyncRouter = (bigquery, db) => {
    const router = Router();

    // 同期処理の状態を取得するエンドポイント
    router.get('/status', (req, res) => {
        res.json(stateManager.getState(JOB_TYPE));
    });

    // 同期処理のエンドポイント
    router.post('/', async (req, res) => {
        if (stateManager.isRunning(JOB_TYPE)) {
            return res.status(409).json({ 
                error: '同期処理は既に実行中です',
                status: stateManager.getState(JOB_TYPE)
            });
        }

        try {
            const { date } = req.body;
            
            if (!date) {
                return res.status(400).json({
                    error: '日付を指定してください',
                    status: stateManager.getState(JOB_TYPE)
                });
            }

            stateManager.startJob(JOB_TYPE);
            stateManager.updateProgress(JOB_TYPE, 0, 0, '同期処理を開始します...');

            // SQLiteのデータを確認
            console.log('検索する日付:', date);
            const data = await sqlite.getDiffDataDate(db, date);
            console.log('検索結果:', data.length, '件');

            if (data.length === 0) {
                stateManager.completeJob(JOB_TYPE, '指定された日付のデータが存在しません');
                return res.status(404).json({ 
                    message: '指定された日付のデータが存在しません',
                    status: stateManager.getState(JOB_TYPE)
                });
            }

            // BigQueryのテーブルを取得（存在しない場合は作成）
            const { datasetId } = BIGQUERY;
            const dateTable = `data_${date.replace(/-/g, '')}`;
            const table = await getTable(bigquery, datasetId, dateTable);

            if (data.length > 0) {
                // BigQueryにデータを保存
                await saveToBigQuery(table, data);
            }

            stateManager.updateProgress(JOB_TYPE, data.length, data.length, '同期処理が完了しました');
            stateManager.completeJob(JOB_TYPE, `同期処理が完了しました (${data.length}件)`);

            res.status(200).json({ 
                message: '同期処理が完了しました',
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
