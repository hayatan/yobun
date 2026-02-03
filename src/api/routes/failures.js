// ============================================================================
// 失敗管理 APIルーター
// ============================================================================
// 
// GET /api/failures - 失敗一覧取得（フィルタ対応）
// GET /api/failures/stats - 統計情報取得
// GET /api/failures/:id - 失敗詳細取得
// PATCH /api/failures/:id - ステータス更新
// DELETE /api/failures/:id - 失敗レコード削除
// ============================================================================

import { Router } from 'express';
import failures from '../../db/sqlite/failures.js';

const createFailuresRouter = (db) => {
    const router = Router();

    /**
     * 失敗一覧取得（フィルタ対応）
     * GET /api/failures?startDate=2026-01-01&endDate=2026-01-31&holes=xxx,yyy&status=pending&limit=100
     * holes: カンマ区切りで複数店舗指定可能
     */
    router.get('/', async (req, res) => {
        try {
            const { startDate, endDate, holes, hole, status, limit } = req.query;
            
            const filters = {};
            if (startDate) filters.startDate = startDate;
            if (endDate) filters.endDate = endDate;
            
            // 複数店舗対応（holes優先）
            if (holes) {
                filters.holes = holes.split(',').map(h => h.trim()).filter(h => h);
            } else if (hole) {
                filters.hole = hole;
            }
            
            if (status) filters.status = status;
            if (limit) filters.limit = parseInt(limit, 10);
            
            const data = await failures.getFailures(db, filters);
            
            res.json({
                success: true,
                count: data.length,
                data,
            });
        } catch (error) {
            console.error('失敗一覧取得エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * 統計情報取得
     * GET /api/failures/stats
     */
    router.get('/stats', async (req, res) => {
        try {
            const stats = await failures.getStats(db);
            
            res.json({
                success: true,
                stats,
            });
        } catch (error) {
            console.error('失敗統計取得エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * 失敗詳細取得
     * GET /api/failures/:id
     */
    router.get('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const data = await failures.getFailureById(db, id);
            
            if (!data) {
                return res.status(404).json({
                    success: false,
                    error: '指定されたIDの失敗レコードが見つかりません',
                });
            }
            
            res.json({
                success: true,
                data,
            });
        } catch (error) {
            console.error('失敗詳細取得エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * ステータス更新
     * PATCH /api/failures/:id
     * Body: { status: 'resolved' | 'ignored', resolvedMethod?: 'manual' | 'rescrape' }
     */
    router.patch('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const { status, resolvedMethod } = req.body;
            
            if (!status) {
                return res.status(400).json({
                    success: false,
                    error: 'statusを指定してください',
                });
            }
            
            // ステータスのバリデーション
            const validStatuses = Object.values(failures.statuses);
            if (!validStatuses.includes(status)) {
                return res.status(400).json({
                    success: false,
                    error: `statusは${validStatuses.join(', ')}のいずれかを指定してください`,
                });
            }
            
            const updated = await failures.updateFailureStatus(db, id, status, resolvedMethod);
            
            if (!updated) {
                return res.status(404).json({
                    success: false,
                    error: '指定されたIDの失敗レコードが見つかりません',
                });
            }
            
            res.json({
                success: true,
                message: 'ステータスを更新しました',
            });
        } catch (error) {
            console.error('失敗ステータス更新エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * 失敗レコード一括削除
     * DELETE /api/failures/bulk
     * Body: { ids: string[] }
     */
    router.delete('/bulk', async (req, res) => {
        try {
            const { ids } = req.body;
            
            if (!ids || !Array.isArray(ids) || ids.length === 0) {
                return res.status(400).json({
                    success: false,
                    error: 'idsは1つ以上の配列で指定してください',
                });
            }
            
            const count = await failures.deleteFailuresBulk(db, ids);
            
            res.json({
                success: true,
                count,
                message: `${count}件の失敗レコードを削除しました`,
            });
        } catch (error) {
            console.error('失敗レコード一括削除エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * 失敗レコード削除
     * DELETE /api/failures/:id
     */
    router.delete('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const deleted = await failures.deleteFailure(db, id);
            
            if (!deleted) {
                return res.status(404).json({
                    success: false,
                    error: '指定されたIDの失敗レコードが見つかりません',
                });
            }
            
            res.json({
                success: true,
                message: '失敗レコードを削除しました',
            });
        } catch (error) {
            console.error('失敗レコード削除エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    return router;
};

export default createFailuresRouter;
