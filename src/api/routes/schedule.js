/**
 * スケジュール管理API v2
 * 
 * エンドポイント:
 * - GET  /api/schedules          - 全ジョブ一覧と履歴
 * - PUT  /api/schedules/:jobId   - ジョブの更新
 * - POST /api/schedules/:jobId/run - ジョブの手動実行
 * - POST /api/schedules/stop     - 実行中ジョブを停止
 * - POST /api/schedules/:jobId/schedules - スケジュール追加
 * - PUT  /api/schedules/:jobId/schedules/:scheduleId - スケジュール更新
 * - DELETE /api/schedules/:jobId/schedules/:scheduleId - スケジュール削除
 */

import { Router } from 'express';
import { 
    loadConfig, 
    updateJob, 
    addSchedule, 
    updateSchedule, 
    deleteSchedule,
    getHistory,
    describeSchedule,
    scheduleToCron,
} from '../../scheduler/storage.js';
import { runJobManually, reloadSchedules, getCurrentJobId, stopCurrentJob } from '../../scheduler/index.js';

const createScheduleRouter = () => {
    const router = Router();
    
    /**
     * GET /api/schedules
     * 全ジョブ一覧と履歴を取得
     */
    router.get('/', async (req, res) => {
        try {
            const config = await loadConfig();
            const history = await getHistory(50);
            
            // 各ジョブにスケジュールの説明を追加
            const jobs = config.jobs.map(job => ({
                ...job,
                schedules: (job.schedules || []).map(s => ({
                    ...s,
                    description: describeSchedule(s),
                    cron: scheduleToCron(s),
                })),
            }));
            
            res.json({
                success: true,
                jobs,
                history,
                updatedAt: config.updatedAt,
                currentJobId: getCurrentJobId(),
            });
        } catch (error) {
            console.error('スケジュール取得エラー:', error);
            res.status(500).json({ success: false, message: error.message });
        }
    });
    
    /**
     * PUT /api/schedules/:jobId
     * ジョブの更新
     */
    router.put('/:jobId', async (req, res) => {
        try {
            const { jobId } = req.params;
            const updates = req.body;
            
            // 許可するフィールド
            const allowedFields = [
                'name', 'description', 'enabled', 
                'runDatamartAfter', 'dateRange', 'options'
            ];
            const filteredUpdates = {};
            for (const field of allowedFields) {
                if (updates[field] !== undefined) {
                    filteredUpdates[field] = updates[field];
                }
            }
            
            const updatedJob = await updateJob(jobId, filteredUpdates);
            
            // スケジュールを再読み込み
            await reloadSchedules();
            
            res.json({
                success: true,
                job: updatedJob,
                message: 'ジョブを更新しました',
            });
        } catch (error) {
            console.error('ジョブ更新エラー:', error);
            res.status(400).json({ success: false, message: error.message });
        }
    });
    
    /**
     * POST /api/schedules/:jobId/run
     * ジョブの手動実行
     */
    router.post('/:jobId/run', async (req, res) => {
        try {
            const { jobId } = req.params;
            
            // 非同期で実行開始（すぐにレスポンス返す）
            runJobManually(jobId).catch(error => {
                console.error('ジョブ手動実行エラー:', error);
            });
            
            res.json({
                success: true,
                message: 'ジョブの実行を開始しました',
            });
        } catch (error) {
            console.error('ジョブ手動実行エラー:', error);
            res.status(500).json({ success: false, message: error.message });
        }
    });
    
    /**
     * POST /api/schedules/stop
     * 実行中ジョブを停止
     */
    router.post('/stop', async (req, res) => {
        try {
            const result = await stopCurrentJob();
            res.json(result);
        } catch (error) {
            console.error('ジョブ停止エラー:', error);
            res.status(500).json({ success: false, message: error.message });
        }
    });
    
    /**
     * POST /api/schedules/:jobId/schedules
     * スケジュール追加
     */
    router.post('/:jobId/schedules', async (req, res) => {
        try {
            const { jobId } = req.params;
            const scheduleData = req.body;
            
            // バリデーション
            if (!scheduleData.type || !['daily', 'interval'].includes(scheduleData.type)) {
                return res.status(400).json({ 
                    success: false, 
                    message: 'スケジュールタイプが無効です (daily または interval)' 
                });
            }
            
            if (scheduleData.type === 'daily') {
                if (typeof scheduleData.hour !== 'number' || scheduleData.hour < 0 || scheduleData.hour > 23) {
                    return res.status(400).json({ success: false, message: '時間は0-23の範囲で指定してください' });
                }
                if (typeof scheduleData.minute !== 'number' || scheduleData.minute < 0 || scheduleData.minute > 59) {
                    return res.status(400).json({ success: false, message: '分は0-59の範囲で指定してください' });
                }
            } else if (scheduleData.type === 'interval') {
                if (typeof scheduleData.intervalHours !== 'number' || scheduleData.intervalHours < 1 || scheduleData.intervalHours > 24) {
                    return res.status(400).json({ success: false, message: '間隔は1-24の範囲で指定してください' });
                }
            }
            
            const newSchedule = await addSchedule(jobId, scheduleData);
            
            // スケジュールを再読み込み
            await reloadSchedules();
            
            res.json({
                success: true,
                schedule: {
                    ...newSchedule,
                    description: describeSchedule(newSchedule),
                    cron: scheduleToCron(newSchedule),
                },
                message: 'スケジュールを追加しました',
            });
        } catch (error) {
            console.error('スケジュール追加エラー:', error);
            res.status(400).json({ success: false, message: error.message });
        }
    });
    
    /**
     * PUT /api/schedules/:jobId/schedules/:scheduleId
     * スケジュール更新
     */
    router.put('/:jobId/schedules/:scheduleId', async (req, res) => {
        try {
            const { jobId, scheduleId } = req.params;
            const updates = req.body;
            
            // バリデーション
            if (updates.type && !['daily', 'interval'].includes(updates.type)) {
                return res.status(400).json({ 
                    success: false, 
                    message: 'スケジュールタイプが無効です (daily または interval)' 
                });
            }
            
            if (updates.type === 'daily' || updates.hour !== undefined || updates.minute !== undefined) {
                if (updates.hour !== undefined && (updates.hour < 0 || updates.hour > 23)) {
                    return res.status(400).json({ success: false, message: '時間は0-23の範囲で指定してください' });
                }
                if (updates.minute !== undefined && (updates.minute < 0 || updates.minute > 59)) {
                    return res.status(400).json({ success: false, message: '分は0-59の範囲で指定してください' });
                }
            }
            
            if (updates.intervalHours !== undefined && (updates.intervalHours < 1 || updates.intervalHours > 24)) {
                return res.status(400).json({ success: false, message: '間隔は1-24の範囲で指定してください' });
            }
            
            const updatedSchedule = await updateSchedule(jobId, scheduleId, updates);
            
            // スケジュールを再読み込み
            await reloadSchedules();
            
            res.json({
                success: true,
                schedule: {
                    ...updatedSchedule,
                    description: describeSchedule(updatedSchedule),
                    cron: scheduleToCron(updatedSchedule),
                },
                message: 'スケジュールを更新しました',
            });
        } catch (error) {
            console.error('スケジュール更新エラー:', error);
            res.status(400).json({ success: false, message: error.message });
        }
    });
    
    /**
     * DELETE /api/schedules/:jobId/schedules/:scheduleId
     * スケジュール削除
     */
    router.delete('/:jobId/schedules/:scheduleId', async (req, res) => {
        try {
            const { jobId, scheduleId } = req.params;
            
            await deleteSchedule(jobId, scheduleId);
            
            // スケジュールを再読み込み
            await reloadSchedules();
            
            res.json({
                success: true,
                message: 'スケジュールを削除しました',
            });
        } catch (error) {
            console.error('スケジュール削除エラー:', error);
            res.status(400).json({ success: false, message: error.message });
        }
    });
    
    return router;
};

export default createScheduleRouter;
