/**
 * スケジュール管理 API ルーター
 * 
 * /api/schedules - スケジュール一覧取得
 * /api/schedules/:id - スケジュール設定変更
 * /api/schedules/:id/run - 手動実行
 * /api/schedules/history - 実行履歴取得
 */

import { Router } from 'express';
import { getScheduleStatus, runJobManually, updateScheduleAndReload } from '../../scheduler/index.js';
import { getHistory } from '../../scheduler/storage.js';

const createScheduleRouter = (bigquery, db) => {
    const router = Router();

    /**
     * スケジュール一覧取得
     * GET /api/schedules
     */
    router.get('/', async (req, res) => {
        try {
            const schedules = await getScheduleStatus();
            res.json({
                success: true,
                schedules,
            });
        } catch (error) {
            console.error('スケジュール一覧取得エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * 実行履歴取得
     * GET /api/schedules/history
     */
    router.get('/history', async (req, res) => {
        try {
            const limit = parseInt(req.query.limit) || 20;
            const history = await getHistory(limit);
            res.json({
                success: true,
                history,
            });
        } catch (error) {
            console.error('実行履歴取得エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * スケジュール設定変更
     * PUT /api/schedules/:id
     */
    router.put('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const updates = req.body;
            
            // 許可するフィールドのみ更新
            const allowedFields = ['name', 'description', 'cron', 'enabled', 'options'];
            const filteredUpdates = {};
            for (const field of allowedFields) {
                if (updates[field] !== undefined) {
                    filteredUpdates[field] = updates[field];
                }
            }
            
            const schedule = await updateScheduleAndReload(id, filteredUpdates, bigquery, db);
            
            res.json({
                success: true,
                schedule,
                message: 'スケジュールを更新しました',
            });
        } catch (error) {
            console.error('スケジュール更新エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * 手動実行
     * POST /api/schedules/:id/run
     */
    router.post('/:id/run', async (req, res) => {
        try {
            const { id } = req.params;
            
            // 非同期で実行開始（すぐにレスポンスを返す）
            res.json({
                success: true,
                message: 'ジョブの実行を開始しました',
                scheduleId: id,
            });
            
            // バックグラウンドで実行
            runJobManually(id, bigquery, db).catch(error => {
                console.error(`手動実行エラー (${id}):`, error);
            });
            
        } catch (error) {
            console.error('手動実行エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * スケジュールの有効/無効切り替え
     * POST /api/schedules/:id/toggle
     */
    router.post('/:id/toggle', async (req, res) => {
        try {
            const { id } = req.params;
            const schedules = await getScheduleStatus();
            const current = schedules.find(s => s.id === id);
            
            if (!current) {
                return res.status(404).json({
                    success: false,
                    error: 'スケジュールが見つかりません',
                });
            }
            
            const schedule = await updateScheduleAndReload(id, { enabled: !current.enabled }, bigquery, db);
            
            res.json({
                success: true,
                schedule,
                message: schedule.enabled ? 'スケジュールを有効化しました' : 'スケジュールを無効化しました',
            });
        } catch (error) {
            console.error('スケジュール切り替えエラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    return router;
};

export default createScheduleRouter;
