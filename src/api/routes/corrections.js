// ============================================================================
// 手動補正 APIルーター
// ============================================================================
// 
// POST /api/corrections - 手動補正データ登録
// GET /api/corrections - 手動補正一覧取得
// GET /api/corrections/summary - 補正サマリー取得
// DELETE /api/corrections/:id - 手動補正削除
// DELETE /api/corrections/bulk - 一括削除
// ============================================================================

import { Router } from 'express';
import corrections from '../../db/sqlite/corrections.js';
import failures from '../../db/sqlite/failures.js';
import sqlite from '../../db/sqlite/operations.js';
import { saveToBigQuery } from '../../db/bigquery/operations.js';
import { BIGQUERY } from '../../config/constants.js';
import { findHoleByName } from '../../config/slorepo-config.js';

const SOURCE = 'slorepo';

const createCorrectionsRouter = (bigquery, db) => {
    const router = Router();

    /**
     * 手動補正データ登録
     * POST /api/corrections
     * Body: {
     *   date: string,
     *   hole: string,
     *   machine: string,
     *   failureId?: string,
     *   notes?: string,
     *   data: Array<{
     *     machineNumber: number,
     *     diff: number,
     *     game: number,
     *     big: number,
     *     reg: number,
     *     combinedRate: string
     *   }>
     * }
     */
    router.post('/', async (req, res) => {
        try {
            const { date, hole, machine, failureId, notes, data } = req.body;
            
            // バリデーション
            if (!date || !hole || !machine || !data || !Array.isArray(data) || data.length === 0) {
                return res.status(400).json({
                    success: false,
                    error: 'date, hole, machine, data（配列）は必須です',
                });
            }
            
            // 店舗の存在確認
            const holeConfig = findHoleByName(hole);
            if (!holeConfig) {
                return res.status(400).json({
                    success: false,
                    error: '指定された店舗が見つかりません',
                });
            }
            
            // データの検証
            for (const row of data) {
                if (typeof row.machineNumber !== 'number') {
                    return res.status(400).json({
                        success: false,
                        error: 'machineNumberは数値である必要があります',
                    });
                }
            }
            
            // 手動補正データを追加
            const count = await corrections.addCorrections(db, {
                date,
                hole,
                machine,
                failureId,
                notes,
                data,
                source: SOURCE,
            });
            
            // scraped_data にもコピー
            const copyCount = await corrections.copyToScrapedData(db, date, hole, machine);
            
            // BigQuery に同期（Load Job使用、重複防止）
            try {
                const { datasetId } = BIGQUERY;
                const tableId = `data_${date.replace(/-/g, '')}`;
                const scrapedData = await sqlite.getDiffData(db, date, hole);
                
                if (scrapedData.length > 0) {
                    // 新形式: saveToBigQuery(bigquery, datasetId, tableId, data, source)
                    await saveToBigQuery(bigquery, datasetId, tableId, scrapedData, SOURCE);
                }
            } catch (bqError) {
                console.error('BigQuery同期エラー:', bqError.message);
                // BigQuery同期エラーは警告として扱う
            }
            
            // 関連する失敗レコードを resolved に更新
            if (failureId) {
                try {
                    await failures.updateFailureStatus(
                        db, 
                        failureId, 
                        failures.statuses.RESOLVED, 
                        failures.resolvedMethods.MANUAL
                    );
                } catch (failureErr) {
                    console.error('失敗レコード更新エラー:', failureErr.message);
                }
            }
            
            res.json({
                success: true,
                message: '手動補正データを登録しました',
                count,
                copyCount,
            });
        } catch (error) {
            console.error('手動補正データ登録エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * 手動補正一覧取得
     * GET /api/corrections?startDate=2026-01-01&endDate=2026-01-31&hole=xxx&machine=xxx&limit=100
     */
    router.get('/', async (req, res) => {
        try {
            const { startDate, endDate, hole, machine, limit } = req.query;
            
            const filters = {};
            if (startDate) filters.startDate = startDate;
            if (endDate) filters.endDate = endDate;
            if (hole) filters.hole = hole;
            if (machine) filters.machine = machine;
            if (limit) filters.limit = parseInt(limit, 10);
            
            const data = await corrections.getCorrections(db, filters);
            
            res.json({
                success: true,
                count: data.length,
                data,
            });
        } catch (error) {
            console.error('手動補正一覧取得エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * 補正サマリー取得（機種単位でグループ化）
     * GET /api/corrections/summary?startDate=2026-01-01&endDate=2026-01-31&hole=xxx
     */
    router.get('/summary', async (req, res) => {
        try {
            const { startDate, endDate, hole } = req.query;
            
            const filters = {};
            if (startDate) filters.startDate = startDate;
            if (endDate) filters.endDate = endDate;
            if (hole) filters.hole = hole;
            
            const data = await corrections.getCorrectionsSummary(db, filters);
            
            res.json({
                success: true,
                count: data.length,
                data,
            });
        } catch (error) {
            console.error('補正サマリー取得エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * 一括削除
     * DELETE /api/corrections/bulk
     * Body: { date: string, hole: string, machine?: string }
     */
    router.delete('/bulk', async (req, res) => {
        try {
            const { date, hole, machine } = req.body;

            if (!date || !hole) {
                return res.status(400).json({
                    success: false,
                    error: 'dateとholeは必須です',
                });
            }

            const count = await corrections.deleteCorrections(db, date, hole, machine);

            res.json({
                success: true,
                message: `${count}件の補正データを削除しました`,
                count,
            });
        } catch (error) {
            console.error('補正データ一括削除エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * 手動補正削除（単一）
     * DELETE /api/corrections/:id
     */
    router.delete('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const deleted = await corrections.deleteCorrection(db, id);

            if (!deleted) {
                return res.status(404).json({
                    success: false,
                    error: '指定されたIDの補正データが見つかりません',
                });
            }

            res.json({
                success: true,
                message: '補正データを削除しました',
            });
        } catch (error) {
            console.error('補正データ削除エラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    /**
     * クリップボードデータをパース
     * POST /api/corrections/parse
     * Body: { text: string }
     */
    router.post('/parse', async (req, res) => {
        try {
            const { text } = req.body;
            
            if (!text) {
                return res.status(400).json({
                    success: false,
                    error: 'textは必須です',
                });
            }
            
            const data = parseTableData(text);
            
            res.json({
                success: true,
                count: data.length,
                data,
            });
        } catch (error) {
            console.error('パースエラー:', error);
            res.status(500).json({
                success: false,
                error: error.message,
            });
        }
    });

    return router;
};

/**
 * スロレポのテーブルデータをパース
 * タブ区切りテキストをオブジェクト配列に変換
 * @param {string} text - タブ区切りテキスト
 * @returns {Array} パース結果
 */
function parseTableData(text) {
    const lines = text.trim().split('\n');
    
    return lines
        .map(line => line.split('\t'))
        .filter(cells => {
            // ヘッダー行と平均行をスキップ
            const firstCell = cells[0]?.trim();
            return firstCell && firstCell !== '台番' && firstCell !== '平均';
        })
        .map(cells => {
            const machineNumber = parseInt(cells[0]?.trim() || '0', 10);
            const diff = parseInt((cells[1] || '0').replace(/[,+]/g, ''), 10);
            const game = parseInt((cells[2] || '0').replace(/,/g, ''), 10);
            const big = parseInt(cells[3]?.trim() || '0', 10);
            const reg = parseInt(cells[4]?.trim() || '0', 10);
            const combinedRate = cells[5]?.trim() || '';
            
            return {
                machineNumber,
                diff,
                game,
                big,
                reg,
                combinedRate,
            };
        })
        .filter(row => !isNaN(row.machineNumber) && row.machineNumber > 0);
}

export default createCorrectionsRouter;
