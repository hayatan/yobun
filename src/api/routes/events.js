// ============================================================================
// イベント APIルーター
// ============================================================================
// 
// GET /api/events - イベント一覧取得（フィルタ対応）
// GET /api/events/:id - イベント詳細取得
// POST /api/events - イベント登録
// PATCH /api/events/:id - イベント更新
// DELETE /api/events/:id - イベント削除
// DELETE /api/events/bulk - イベント一括削除
// POST /api/events/sync - BigQuery同期
// ============================================================================

import { Router } from 'express';
import events from '../../db/sqlite/events.js';
import { syncEvents } from '../../db/bigquery/events.js';

const createEventsRouter = (bigquery, db) => {
    const router = Router();

    /**
     * イベント一覧取得（フィルタ対応）
     * GET /api/events?startDate=2026-01-01&endDate=2026-01-31&hole=xxx&event=LINE告知&limit=100
     */
    router.get('/', async (req, res) => {
        try {
            const { startDate, endDate, hole, event, limit } = req.query;
            
            const filters = {};
            if (startDate) filters.startDate = startDate;
            if (endDate) filters.endDate = endDate;
            if (hole) filters.hole = hole;
            if (event) filters.event = event;
            if (limit) filters.limit = parseInt(limit, 10);
            
            const data = await events.getEvents(db, filters);
            
            res.json({
                success: true,
                count: data.length,
                data,
            });
        } catch (error) {
            console.error('イベント一覧取得エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * メタ情報取得（イベント種類・店舗一覧）
     * GET /api/events/meta/info
     */
    router.get('/meta/info', async (req, res) => {
        try {
            const [eventTypes, holes] = await Promise.all([
                events.getDistinctEventTypes(db),
                events.getDistinctHoles(db),
            ]);

            res.json({
                success: true,
                eventTypes,
                holes,
            });
        } catch (error) {
            console.error('イベントメタ情報取得エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * イベント詳細取得
     * GET /api/events/:id
     */
    router.get('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const data = await events.getEventById(db, id);
            
            if (!data) {
                return res.status(404).json({
                    success: false,
                    error: '指定されたIDのイベントが見つかりません',
                });
            }
            
            res.json({
                success: true,
                data,
            });
        } catch (error) {
            console.error('イベント詳細取得エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * イベント登録
     * POST /api/events
     * Body: { date, hole, event, description? }
     */
    router.post('/', async (req, res) => {
        try {
            const { date, hole, event, description } = req.body;
            
            // バリデーション
            if (!date || !hole || !event) {
                return res.status(400).json({
                    success: false,
                    error: 'date, hole, eventは必須です',
                });
            }
            
            // 日付フォーマットチェック
            if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
                return res.status(400).json({
                    success: false,
                    error: 'dateはYYYY-MM-DD形式で指定してください',
                });
            }
            
            const id = await events.addEvent(db, { date, hole, event, description });
            
            res.status(201).json({
                success: true,
                id,
                message: 'イベントを登録しました',
            });
        } catch (error) {
            console.error('イベント登録エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * イベント一括登録
     * POST /api/events/bulk
     * Body: { events: [{ date, hole, event, description? }, ...] }
     */
    router.post('/bulk', async (req, res) => {
        try {
            const { events: eventList } = req.body;
            
            // バリデーション
            if (!eventList || !Array.isArray(eventList) || eventList.length === 0) {
                return res.status(400).json({
                    success: false,
                    error: 'eventsは1つ以上の配列で指定してください',
                });
            }
            
            // 各イベントのバリデーション
            for (let i = 0; i < eventList.length; i++) {
                const { date, hole, event } = eventList[i];
                if (!date || !hole || !event) {
                    return res.status(400).json({
                        success: false,
                        error: `events[${i}]: date, hole, eventは必須です`,
                    });
                }
                if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
                    return res.status(400).json({
                        success: false,
                        error: `events[${i}]: dateはYYYY-MM-DD形式で指定してください`,
                    });
                }
            }
            
            const count = await events.addEventsBulk(db, eventList);
            
            res.status(201).json({
                success: true,
                count,
                message: `${count}件のイベントを登録しました`,
            });
        } catch (error) {
            console.error('イベント一括登録エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * イベント更新
     * PATCH /api/events/:id
     * Body: { date?, hole?, event?, description? }
     */
    router.patch('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const { date, hole, event, description } = req.body;
            
            // 日付フォーマットチェック
            if (date && !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
                return res.status(400).json({
                    success: false,
                    error: 'dateはYYYY-MM-DD形式で指定してください',
                });
            }
            
            const updates = {};
            if (date !== undefined) updates.date = date;
            if (hole !== undefined) updates.hole = hole;
            if (event !== undefined) updates.event = event;
            if (description !== undefined) updates.description = description;
            
            if (Object.keys(updates).length === 0) {
                return res.status(400).json({
                    success: false,
                    error: '更新する項目を指定してください',
                });
            }
            
            const updated = await events.updateEvent(db, id, updates);
            
            if (!updated) {
                return res.status(404).json({
                    success: false,
                    error: '指定されたIDのイベントが見つかりません',
                });
            }
            
            res.json({
                success: true,
                message: 'イベントを更新しました',
            });
        } catch (error) {
            console.error('イベント更新エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * イベント一括削除
     * DELETE /api/events/bulk
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
            
            const count = await events.deleteEventsBulk(db, ids);
            
            res.json({
                success: true,
                count,
                message: `${count}件のイベントを削除しました`,
            });
        } catch (error) {
            console.error('イベント一括削除エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * イベント削除
     * DELETE /api/events/:id
     */
    router.delete('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const deleted = await events.deleteEvent(db, id);
            
            if (!deleted) {
                return res.status(404).json({
                    success: false,
                    error: '指定されたIDのイベントが見つかりません',
                });
            }
            
            res.json({
                success: true,
                message: 'イベントを削除しました',
            });
        } catch (error) {
            console.error('イベント削除エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * BigQuery同期
     * POST /api/events/sync
     */
    router.post('/sync', async (req, res) => {
        try {
            // SQLiteから全イベントを取得
            const allEvents = await events.getAllEvents(db);
            
            // BigQueryに同期
            const count = await syncEvents(bigquery, allEvents);
            
            res.json({
                success: true,
                count,
                message: `${count}件のイベントをBigQueryに同期しました`,
            });
        } catch (error) {
            console.error('イベントBigQuery同期エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    return router;
};

export default createEventsRouter;
