// ============================================================================
// イベントタイプ APIルーター
// ============================================================================
// 
// GET /api/event-types - イベントタイプ一覧取得
// POST /api/event-types - イベントタイプ登録
// PATCH /api/event-types/:id - イベントタイプ更新
// DELETE /api/event-types/:id - イベントタイプ削除
// ============================================================================

import { Router } from 'express';
import eventTypes from '../../db/sqlite/event-types.js';

const createEventTypesRouter = (db) => {
    const router = Router();

    /**
     * イベントタイプ一覧取得
     * GET /api/event-types
     */
    router.get('/', async (req, res) => {
        try {
            const data = await eventTypes.getEventTypes(db);
            
            res.json({
                success: true,
                count: data.length,
                data,
            });
        } catch (error) {
            console.error('イベントタイプ一覧取得エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * イベントタイプ詳細取得
     * GET /api/event-types/:id
     */
    router.get('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const data = await eventTypes.getEventTypeById(db, id);
            
            if (!data) {
                return res.status(404).json({
                    success: false,
                    error: '指定されたIDのイベントタイプが見つかりません',
                });
            }
            
            res.json({
                success: true,
                data,
            });
        } catch (error) {
            console.error('イベントタイプ詳細取得エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * イベントタイプ登録
     * POST /api/event-types
     * Body: { name, sortOrder? }
     */
    router.post('/', async (req, res) => {
        try {
            const { name, sortOrder } = req.body;
            
            // バリデーション
            if (!name || typeof name !== 'string' || name.trim() === '') {
                return res.status(400).json({
                    success: false,
                    error: 'nameは必須です',
                });
            }
            
            const id = await eventTypes.addEventType(db, { 
                name: name.trim(), 
                sortOrder: sortOrder !== undefined ? parseInt(sortOrder, 10) : 0,
            });
            
            res.status(201).json({
                success: true,
                id,
                message: 'イベントタイプを登録しました',
            });
        } catch (error) {
            console.error('イベントタイプ登録エラー:', error);
            
            // 重複エラーの場合は400を返す
            if (error.message.includes('既に存在します')) {
                return res.status(400).json({
                    success: false,
                    error: error.message,
                });
            }
            
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * イベントタイプ更新
     * PATCH /api/event-types/:id
     * Body: { name?, sortOrder? }
     */
    router.patch('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const { name, sortOrder } = req.body;
            
            const updates = {};
            if (name !== undefined) {
                if (typeof name !== 'string' || name.trim() === '') {
                    return res.status(400).json({
                        success: false,
                        error: 'nameは空文字にできません',
                    });
                }
                updates.name = name.trim();
            }
            if (sortOrder !== undefined) {
                updates.sortOrder = parseInt(sortOrder, 10);
            }
            
            if (Object.keys(updates).length === 0) {
                return res.status(400).json({
                    success: false,
                    error: '更新する項目を指定してください',
                });
            }
            
            const updated = await eventTypes.updateEventType(db, id, updates);
            
            if (!updated) {
                return res.status(404).json({
                    success: false,
                    error: '指定されたIDのイベントタイプが見つかりません',
                });
            }
            
            res.json({
                success: true,
                message: 'イベントタイプを更新しました',
            });
        } catch (error) {
            console.error('イベントタイプ更新エラー:', error);
            
            // 重複エラーの場合は400を返す
            if (error.message.includes('既に存在します')) {
                return res.status(400).json({
                    success: false,
                    error: error.message,
                });
            }
            
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * イベントタイプ削除
     * DELETE /api/event-types/:id
     */
    router.delete('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const deleted = await eventTypes.deleteEventType(db, id);
            
            if (!deleted) {
                return res.status(404).json({
                    success: false,
                    error: '指定されたIDのイベントタイプが見つかりません',
                });
            }
            
            res.json({
                success: true,
                message: 'イベントタイプを削除しました',
            });
        } catch (error) {
            console.error('イベントタイプ削除エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    return router;
};

export default createEventTypesRouter;
