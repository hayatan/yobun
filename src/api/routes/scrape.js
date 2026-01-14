// ============================================================================
// スクレイピング ルーター
// ============================================================================
// 
// /pubsub - Pub/Subからのスクレイピング実行
// /status - スクレイピング状態取得
// ============================================================================

import { Router } from 'express';
import stateManager from '../state-manager.js';
import { runScrape } from '../../app.js';

const JOB_TYPE = 'scraping';

const createScrapeRouter = (bigquery, db) => {
    const router = Router();

    // スクレイピングの状態を取得するエンドポイント
    router.get('/status', (req, res) => {
        res.json(stateManager.getState(JOB_TYPE));
    });

    // Pub/Subメッセージを処理するエンドポイント
    router.post('/pubsub', async (req, res) => {
        if (stateManager.isRunning(JOB_TYPE)) {
            return res.status(409).json({ 
                error: 'スクレイピングは既に実行中です',
                status: stateManager.getState(JOB_TYPE)
            });
        }

        try {
            const { startDate, endDate, continueOnError, force, prioritizeHigh } = req.body;
            
            if (!startDate || !endDate) {
                return res.status(400).json({
                    error: '開始日と終了日を指定してください',
                    status: stateManager.getState(JOB_TYPE)
                });
            }

            stateManager.startJob(JOB_TYPE);

            // 進捗更新コールバック
            const updateProgress = (current, total, message) => {
                stateManager.updateProgress(JOB_TYPE, current, total, message);
            };

            // 非同期でスクレイピングを実行
            runScrape(bigquery, db, updateProgress, { 
                startDate, 
                endDate,
                continueOnError: continueOnError !== false, // デフォルトtrue
                force: force === true,
                prioritizeHigh: prioritizeHigh === true,
            })
                .then((result) => {
                    const message = `完了: 成功=${result.success.length}, 失敗=${result.failed.length}`;
                    stateManager.completeJob(JOB_TYPE, message);
                })
                .catch(error => {
                    stateManager.failJob(JOB_TYPE, error.message);
                });

            res.status(202).json({ 
                message: 'スクレイピングを開始しました',
                status: stateManager.getState(JOB_TYPE)
            });
        } catch (error) {
            stateManager.failJob(JOB_TYPE, error.message);
            res.status(500).json({ 
                error: 'スクレイピングの開始に失敗しました',
                status: stateManager.getState(JOB_TYPE)
            });
        }
    });

    return router;
};

export default createScrapeRouter;
