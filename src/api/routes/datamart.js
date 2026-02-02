// ============================================================================
// データマート管理 ルーター
// ============================================================================
// 
// /api/datamart/status - データマートの日付別件数を取得
// /api/datamart/delete - 指定日付・店舗のデータを削除
// /api/datamart/run - 指定日付範囲でデータマート再実行
// ============================================================================

import { Router } from 'express';
import { runDatamartUpdate, rebuildDatamart } from '../../services/datamart/runner.js';
import { getHoles } from '../../config/slorepo-config.js';
import { DATAMART } from '../../config/constants.js';
import stateManager from '../state-manager.js';

const JOB_TYPE = 'datamart';

const createDatamartRouter = (bigquery, db) => {
    const router = Router();

    /**
     * データマート状況を取得
     * GET /api/datamart/status?start=YYYY-MM-DD&end=YYYY-MM-DD
     */
    router.get('/status', async (req, res) => {
        try {
            const { start, end } = req.query;
            
            if (!start || !end) {
                return res.status(400).json({
                    error: '開始日(start)と終了日(end)を指定してください'
                });
            }

            // BigQueryからデータマートの件数を取得
            // 注意: machine_statsテーブルは target_date カラムを使用し、win カラムは存在しない
            const sql = `
                SELECT 
                    target_date as date,
                    hole,
                    COUNT(*) as count,
                    SUM(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) as win_count,
                    AVG(d1_diff) as avg_diff
                FROM \`yobun-450512.datamart.machine_stats\`
                WHERE target_date BETWEEN @start AND @end
                GROUP BY target_date, hole
                ORDER BY target_date DESC, hole
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
                    totalWinCount: 0,
                });
            }

            // データを集計
            rows.forEach(row => {
                // target_date を date として扱う（SQLでASで変換済み）
                const dateStr = row.date?.value || row.date; // DATE型の場合は.valueで取得
                const dateData = dateMap.get(dateStr);
                if (dateData) {
                    dateData.holes[row.hole] = {
                        count: row.count,
                        winCount: row.win_count,
                        avgDiff: Math.round(row.avg_diff || 0),
                    };
                    dateData.totalCount += row.count;
                    dateData.totalWinCount += row.win_count;
                }
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
                    totalRecords: Array.from(dateMap.values()).reduce((sum, d) => sum + d.totalCount, 0),
                    totalWins: Array.from(dateMap.values()).reduce((sum, d) => sum + d.totalWinCount, 0),
                },
            };

            res.json(response);

        } catch (error) {
            console.error('データマート状況の取得中にエラーが発生しました:', error);
            res.status(500).json({
                error: 'データマート状況の取得中にエラーが発生しました',
                message: error.message,
            });
        }
    });

    /**
     * データマート削除
     * DELETE /api/datamart/delete
     * Body: { date, hole? }  // hole省略時は全店舗
     */
    router.delete('/delete', async (req, res) => {
        try {
            const { date, hole } = req.body;
            
            if (!date) {
                return res.status(400).json({
                    error: '日付(date)を指定してください'
                });
            }

            console.log(`データマート削除開始: ${date}, 店舗: ${hole || '全店舗'}`);

            let deleteQuery;
            let params;
            
            if (hole) {
                deleteQuery = `
                    DELETE FROM \`yobun-450512.datamart.machine_stats\`
                    WHERE target_date = @date AND hole = @hole
                `;
                params = { date, hole };
            } else {
                deleteQuery = `
                    DELETE FROM \`yobun-450512.datamart.machine_stats\`
                    WHERE target_date = @date
                `;
                params = { date };
            }
            
            const [job] = await bigquery.createQueryJob({
                query: deleteQuery,
                params,
                location: 'US',
            });
            
            await job.getQueryResults();
            const metadata = await job.getMetadata();
            const numDeletedRows = metadata[0]?.statistics?.query?.numDmlAffectedRows || 0;

            console.log(`データマート削除完了: ${numDeletedRows} 件`);

            res.json({
                success: true,
                message: 'データマートを削除しました',
                deleted: parseInt(numDeletedRows),
                date,
                hole: hole || '全店舗',
            });

        } catch (error) {
            console.error('データマート削除中にエラーが発生しました:', error);
            res.status(500).json({
                error: 'データマート削除中にエラーが発生しました',
                message: error.message,
            });
        }
    });

    /**
     * データマート再実行（バックフィル）
     * POST /api/datamart/run
     * Body: { startDate, endDate, concurrency? }
     * 
     * 指定した日付範囲の各日付を target_date としてデータマートを再構築する。
     * 例: startDate='2026-01-07', endDate='2026-01-09' を指定
     *     → target_date = '2026-01-07', '2026-01-08', '2026-01-09' の3日分を実行
     * 
     * concurrency: 同時実行数（デフォルト: 5、最大: 10）
     */
    router.post('/run', async (req, res) => {
        if (stateManager.isRunning(JOB_TYPE)) {
            return res.status(409).json({ 
                error: 'データマート処理は既に実行中です',
                status: stateManager.getState(JOB_TYPE)
            });
        }

        try {
            const { startDate, endDate, concurrency: requestedConcurrency } = req.body;
            
            if (!startDate || !endDate) {
                return res.status(400).json({
                    error: '開始日(startDate)と終了日(endDate)を指定してください'
                });
            }

            // 同時実行数を制限（設定値を参照）
            const { default: defaultConcurrency, min, max } = DATAMART.concurrency;
            const concurrency = Math.min(Math.max(requestedConcurrency || defaultConcurrency, min), max);

            stateManager.startJob(JOB_TYPE);
            stateManager.updateProgress(JOB_TYPE, 0, 1, `データマート更新を開始します... (並列数: ${concurrency})`);

            // 非同期で実行
            (async () => {
                try {
                    const results = await rebuildDatamart(startDate, endDate, { concurrency });
                    const successCount = results.filter(r => r.success).length;
                    const failCount = results.filter(r => !r.success).length;
                    
                    stateManager.completeJob(JOB_TYPE, `完了: 成功=${successCount}, 失敗=${failCount}`);
                } catch (error) {
                    console.error('データマート再実行中にエラーが発生しました:', error);
                    stateManager.failJob(JOB_TYPE, error.message);
                }
            })();

            res.status(202).json({ 
                message: 'データマート更新を開始しました',
                note: '指定した日付がそのままtarget_dateになります',
                period: { startDate, endDate },
                concurrency,
                status: stateManager.getState(JOB_TYPE)
            });

        } catch (error) {
            stateManager.failJob(JOB_TYPE, error.message);
            res.status(500).json({ 
                error: 'データマート更新の開始に失敗しました',
                message: error.message,
            });
        }
    });

    /**
     * データマート処理の状態を取得
     * GET /api/datamart/status/job
     */
    router.get('/status/job', (req, res) => {
        res.json(stateManager.getState(JOB_TYPE));
    });

    return router;
};

export default createDatamartRouter;
