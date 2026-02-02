// ============================================================================
// データ取得状況 ルーター
// ============================================================================
// 
// /api/data-status - データ取得状況を取得
// /api/data-status/raw - 生データ削除（DELETE）
// ============================================================================

import { Router } from 'express';
import config, { getHoles } from '../../config/slorepo-config.js';
import sqlite from '../../db/sqlite/operations.js';
import util from '../../util/common.js';
import { deleteBigQueryTable } from '../../db/bigquery/operations.js';
import { BIGQUERY } from '../../config/constants.js';

const createDataStatusRouter = (bigquery, db) => {
    const router = Router();

    /**
     * データ取得状況を取得
     * GET /api/data-status?start=YYYY-MM-DD&end=YYYY-MM-DD
     */
    router.get('/', async (req, res) => {
        try {
            const { start, end } = req.query;
            
            if (!start || !end) {
                return res.status(400).json({
                    error: '開始日(start)と終了日(end)を指定してください'
                });
            }

            // BigQueryから期間内のデータ件数を店舗・日付別に集計
            const sql = `
                SELECT 
                    date,
                    hole,
                    COUNT(*) as count,
                    MAX(timestamp) as last_updated
                FROM \`yobun-450512.scraped_data.data_*\`
                WHERE 
                    _TABLE_SUFFIX BETWEEN REPLACE(@start, '-', '') AND REPLACE(@end, '-', '')
                    AND date BETWEEN @start AND @end
                GROUP BY date, hole
                ORDER BY date DESC, hole
            `;

            const options = {
                query: sql,
                params: { start, end },
                location: 'US',
            };

            const [rows] = await bigquery.query(options);

            // 店舗情報を取得
            const holes = getHoles({ active: true });
            const holeNames = holes.map(h => h.name);
            const priorityHoles = holes.filter(h => h.lateUpdate).map(h => h.name);

            // 日付ごとにデータを整理
            const dateMap = new Map();
            
            // 日付範囲を生成
            const startDate = new Date(start);
            const endDate = new Date(end);
            for (let d = new Date(startDate); d <= endDate; d.setDate(d.getDate() + 1)) {
                const dateStr = d.toISOString().split('T')[0];
                dateMap.set(dateStr, {
                    date: dateStr,
                    holes: {},
                    totalCount: 0,
                    priorityComplete: false,
                    allComplete: false,
                });
            }

            // データを集計
            rows.forEach(row => {
                const dateData = dateMap.get(row.date);
                if (dateData) {
                    dateData.holes[row.hole] = {
                        count: row.count,
                        lastUpdated: row.last_updated?.value || row.last_updated,
                    };
                    dateData.totalCount += row.count;
                }
            });

            // 完了状態を計算
            dateMap.forEach((dateData) => {
                const acquiredHoles = Object.keys(dateData.holes);
                dateData.priorityComplete = priorityHoles.every(h => acquiredHoles.includes(h));
                dateData.allComplete = holeNames.every(h => acquiredHoles.includes(h));
                dateData.acquiredCount = acquiredHoles.length;
                dateData.totalHoles = holeNames.length;
            });

            // レスポンスを作成
            const response = {
                period: { start, end },
                holes: holes.map(h => ({
                    name: h.name,
                    priority: h.lateUpdate ? 'high' : 'normal',
                    region: h.region,
                })),
                data: Array.from(dateMap.values()).sort((a, b) => b.date.localeCompare(a.date)),
                summary: {
                    totalDates: dateMap.size,
                    priorityCompleteDates: Array.from(dateMap.values()).filter(d => d.priorityComplete).length,
                    allCompleteDates: Array.from(dateMap.values()).filter(d => d.allComplete).length,
                },
            };

            res.json(response);

        } catch (error) {
            console.error('データ取得状況の取得中にエラーが発生しました:', error);
            res.status(500).json({
                error: 'データ取得状況の取得中にエラーが発生しました',
                message: error.message,
            });
        }
    });

    /**
     * 特定の日付・店舗のデータ詳細を取得
     * GET /api/data-status/:date/:hole
     */
    router.get('/:date/:hole', async (req, res) => {
        try {
            const { date, hole } = req.params;

            const sql = `
                SELECT 
                    date,
                    hole,
                    machine,
                    machine_number,
                    diff,
                    game,
                    big,
                    reg,
                    combined_rate,
                    win,
                    timestamp
                FROM \`yobun-450512.scraped_data.data_${date.replace(/-/g, '')}\`
                WHERE date = @date AND hole = @hole
                ORDER BY machine, machine_number
            `;

            const options = {
                query: sql,
                params: { date, hole },
                location: 'US',
            };

            const [rows] = await bigquery.query(options);

            res.json({
                date,
                hole,
                count: rows.length,
                data: rows,
            });

        } catch (error) {
            console.error('データ詳細の取得中にエラーが発生しました:', error);
            res.status(500).json({
                error: 'データ詳細の取得中にエラーが発生しました',
                message: error.message,
            });
        }
    });

    /**
     * 生データ削除
     * DELETE /api/data-status/raw
     * Body: { startDate, endDate, hole? }  // hole省略時は全店舗
     */
    router.delete('/raw', async (req, res) => {
        try {
            const { startDate, endDate, hole } = req.body;
            
            if (!startDate || !endDate) {
                return res.status(400).json({
                    error: '開始日(startDate)と終了日(endDate)を指定してください'
                });
            }

            console.log(`生データ削除開始: ${startDate}〜${endDate}, 店舗: ${hole || '全店舗'}`);

            // SQLiteから削除
            const sqliteDeleted = await sqlite.deleteDiffDataRange(db, startDate, endDate, hole || null);
            console.log(`SQLiteから ${sqliteDeleted} 件削除しました`);

            // BigQueryから削除
            let bqDeleted = 0;
            let bqTablesDeleted = 0;
            const bqErrors = [];
            
            // 日付範囲を生成してテーブルごとに削除
            const dateRange = util.generateDateRange(new Date(startDate), new Date(endDate));
            
            for (const date of dateRange) {
                const tableId = `data_${date.replace(/-/g, '')}`;
                const tableName = `\`yobun-450512.scraped_data.${tableId}\``;
                
                try {
                    if (hole) {
                        // 特定店舗の場合: DELETEクエリを使用
                        const deleteQuery = `DELETE FROM ${tableName} WHERE date = @date AND hole = @hole`;
                        const params = { date, hole };
                        
                        const [job] = await bigquery.createQueryJob({
                            query: deleteQuery,
                            params,
                            location: 'US',
                        });
                        
                        const [results] = await job.getQueryResults();
                        const metadata = await job.getMetadata();
                        const numDeletedRows = metadata[0]?.statistics?.query?.numDmlAffectedRows || 0;
                        bqDeleted += parseInt(numDeletedRows);
                        console.log(`[${date}] BigQueryから ${numDeletedRows} 件削除`);
                    } else {
                        // 全店舗の場合: テーブル全体を削除（ストリーミングバッファー対策）
                        const table = bigquery.dataset(BIGQUERY.datasetId).table(tableId);
                        await deleteBigQueryTable(table);
                        bqTablesDeleted++;
                        console.log(`[${date}] BigQueryテーブル全体を削除`);
                    }
                } catch (tableError) {
                    // テーブルが存在しない場合はスキップ
                    if (tableError.message.includes('Not found: Table') || tableError.code === 404) {
                        console.log(`[${date}] テーブルが存在しないためスキップ`);
                    } else if (tableError.message.includes('streaming buffer')) {
                        // ストリーミングバッファーエラーの場合は警告として記録（特定店舗削除時のみ発生）
                        console.warn(`[${date}] BigQuery削除スキップ: ストリーミングバッファーにデータがあります`);
                        bqErrors.push({
                            date,
                            error: 'ストリーミングバッファーにデータがあります。数時間後に再試行してください。',
                        });
                    } else {
                        throw tableError;
                    }
                }
            }

            const bqDeletedInfo = hole 
                ? `BigQuery ${bqDeleted} 件` 
                : `BigQueryテーブル ${bqTablesDeleted} 個削除`;
            console.log(`生データ削除完了: SQLite ${sqliteDeleted} 件, ${bqDeletedInfo}`);

            // レスポンスを作成
            const deletedInfo = hole
                ? { sqlite: sqliteDeleted, bigquery: bqDeleted }
                : { sqlite: sqliteDeleted, bigqueryTables: bqTablesDeleted };
            
            // ストリーミングバッファーエラーがある場合は警告付きで返す
            if (bqErrors.length > 0) {
                res.json({
                    success: true,
                    message: '生データを削除しました（一部のBigQueryテーブルはストリーミングバッファーのためスキップ）',
                    deleted: deletedInfo,
                    warnings: bqErrors,
                    period: { startDate, endDate },
                    hole: hole || '全店舗',
                });
            } else {
                res.json({
                    success: true,
                    message: '生データを削除しました',
                    deleted: deletedInfo,
                    period: { startDate, endDate },
                    hole: hole || '全店舗',
                });
            }

        } catch (error) {
            console.error('生データ削除中にエラーが発生しました:', error);
            res.status(500).json({
                error: '生データ削除中にエラーが発生しました',
                message: error.message,
            });
        }
    });

    return router;
};

export default createDataStatusRouter;
