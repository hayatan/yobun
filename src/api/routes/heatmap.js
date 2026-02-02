// ============================================================================
// ヒートマップ ルーター
// ============================================================================
// 
// /api/heatmap/data - 台別統計データを取得（BigQuery machine_stats）
// /api/heatmap/layouts - レイアウト一覧を取得
// /api/heatmap/layouts/:hole - 特定店舗のレイアウトを取得/保存
// 
// ストレージ: GCS優先、ローカルファイルをfallbackとして使用
// ============================================================================

import { Router } from 'express';
import layoutStorage from '../../config/heatmap-layouts/storage.js';

const createHeatmapRouter = (bigquery) => {
    const router = Router();

    /**
     * 台別統計データを取得
     * GET /api/heatmap/data?hole=アイランド秋葉原店&targetDate=2026-02-02
     * 
     * レスポンス: すべてのメトリクス（prev_除外）を含む
     */
    router.get('/data', async (req, res) => {
        try {
            const { hole, targetDate } = req.query;
            
            if (!hole) {
                return res.status(400).json({
                    error: '店舗名(hole)を指定してください'
                });
            }

            // targetDateが指定されていない場合は最新日を取得
            let actualTargetDate = targetDate;
            if (!actualTargetDate) {
                const latestQuery = `
                    SELECT MAX(target_date) as latest_date
                    FROM \`yobun-450512.datamart.machine_stats\`
                    WHERE hole = @hole
                `;
                const [latestRows] = await bigquery.query({
                    query: latestQuery,
                    params: { hole },
                    location: 'US',
                });
                if (latestRows.length > 0 && latestRows[0].latest_date) {
                    const dateValue = latestRows[0].latest_date;
                    actualTargetDate = dateValue.value || dateValue;
                }
            }

            if (!actualTargetDate) {
                return res.status(404).json({
                    error: '指定された店舗のデータが見つかりません'
                });
            }

            // データ取得クエリ（prev_以外のすべてのメトリクス）
            const sql = `
                SELECT 
                    machine_number,
                    machine,
                    start_date,
                    -- d1
                    d1_diff,
                    d1_game,
                    d1_payout_rate,
                    -- d2
                    d2_diff,
                    d2_game,
                    d2_win_rate,
                    d2_payout_rate,
                    -- d3
                    d3_diff,
                    d3_game,
                    d3_win_rate,
                    d3_payout_rate,
                    -- d4
                    d4_diff,
                    d4_game,
                    d4_win_rate,
                    d4_payout_rate,
                    -- d5
                    d5_diff,
                    d5_game,
                    d5_win_rate,
                    d5_payout_rate,
                    -- d6
                    d6_diff,
                    d6_game,
                    d6_win_rate,
                    d6_payout_rate,
                    -- d7
                    d7_diff,
                    d7_game,
                    d7_win_rate,
                    d7_payout_rate,
                    -- d14
                    d14_diff,
                    d14_game,
                    d14_win_rate,
                    d14_payout_rate,
                    -- d28
                    d28_diff,
                    d28_game,
                    d28_win_rate,
                    d28_payout_rate,
                    -- mtd
                    mtd_diff,
                    mtd_game,
                    mtd_win_rate,
                    mtd_payout_rate,
                    -- all
                    all_diff,
                    all_game,
                    all_win_rate,
                    all_payout_rate,
                    all_days
                FROM \`yobun-450512.datamart.machine_stats\`
                WHERE hole = @hole AND target_date = @targetDate
            `;

            const [rows] = await bigquery.query({
                query: sql,
                params: { hole, targetDate: actualTargetDate },
                location: 'US',
            });

            // 台番号をキーにしたオブジェクトに変換
            const machines = {};
            rows.forEach(row => {
                const machineNumber = row.machine_number;
                machines[machineNumber] = {
                    machine: row.machine,
                    start_date: row.start_date?.value || row.start_date,
                    // d1
                    d1_diff: row.d1_diff,
                    d1_game: row.d1_game,
                    d1_payout_rate: row.d1_payout_rate,
                    // d2
                    d2_diff: row.d2_diff,
                    d2_game: row.d2_game,
                    d2_win_rate: row.d2_win_rate,
                    d2_payout_rate: row.d2_payout_rate,
                    // d3
                    d3_diff: row.d3_diff,
                    d3_game: row.d3_game,
                    d3_win_rate: row.d3_win_rate,
                    d3_payout_rate: row.d3_payout_rate,
                    // d4
                    d4_diff: row.d4_diff,
                    d4_game: row.d4_game,
                    d4_win_rate: row.d4_win_rate,
                    d4_payout_rate: row.d4_payout_rate,
                    // d5
                    d5_diff: row.d5_diff,
                    d5_game: row.d5_game,
                    d5_win_rate: row.d5_win_rate,
                    d5_payout_rate: row.d5_payout_rate,
                    // d6
                    d6_diff: row.d6_diff,
                    d6_game: row.d6_game,
                    d6_win_rate: row.d6_win_rate,
                    d6_payout_rate: row.d6_payout_rate,
                    // d7
                    d7_diff: row.d7_diff,
                    d7_game: row.d7_game,
                    d7_win_rate: row.d7_win_rate,
                    d7_payout_rate: row.d7_payout_rate,
                    // d14
                    d14_diff: row.d14_diff,
                    d14_game: row.d14_game,
                    d14_win_rate: row.d14_win_rate,
                    d14_payout_rate: row.d14_payout_rate,
                    // d28
                    d28_diff: row.d28_diff,
                    d28_game: row.d28_game,
                    d28_win_rate: row.d28_win_rate,
                    d28_payout_rate: row.d28_payout_rate,
                    // mtd
                    mtd_diff: row.mtd_diff,
                    mtd_game: row.mtd_game,
                    mtd_win_rate: row.mtd_win_rate,
                    mtd_payout_rate: row.mtd_payout_rate,
                    // all
                    all_diff: row.all_diff,
                    all_game: row.all_game,
                    all_win_rate: row.all_win_rate,
                    all_payout_rate: row.all_payout_rate,
                    all_days: row.all_days,
                };
            });

            res.json({
                targetDate: actualTargetDate,
                hole,
                machineCount: Object.keys(machines).length,
                machines,
            });

        } catch (error) {
            console.error('ヒートマップデータ取得中にエラーが発生しました:', error);
            res.status(500).json({
                error: 'ヒートマップデータの取得中にエラーが発生しました',
                message: error.message,
            });
        }
    });

    /**
     * レイアウト一覧を取得
     * GET /api/heatmap/layouts
     * 
     * GCSとローカルの両方からレイアウトを取得し、マージして返す（GCS優先）
     */
    router.get('/layouts', async (req, res) => {
        try {
            const layouts = await layoutStorage.listLayouts();
            res.json({ layouts });
        } catch (error) {
            console.error('レイアウト一覧取得中にエラーが発生しました:', error);
            res.status(500).json({
                error: 'レイアウト一覧の取得中にエラーが発生しました',
                message: error.message,
            });
        }
    });

    /**
     * 特定店舗のレイアウトを取得
     * GET /api/heatmap/layouts/:hole
     * 
     * GCS優先、ローカルファイルをfallbackとして使用
     */
    router.get('/layouts/:hole', async (req, res) => {
        try {
            const hole = decodeURIComponent(req.params.hole);
            const { layout, source } = await layoutStorage.loadLayout(hole);
            
            if (!layout) {
                const filename = layoutStorage.holeToFilename(hole);
                return res.status(404).json({
                    error: `店舗「${hole}」のレイアウトが見つかりません`,
                    filename,
                });
            }
            
            // ソース情報をヘッダーに追加
            res.set('X-Layout-Source', source);
            res.json(layout);
        } catch (error) {
            console.error('レイアウト取得中にエラーが発生しました:', error);
            res.status(500).json({
                error: 'レイアウトの取得中にエラーが発生しました',
                message: error.message,
            });
        }
    });

    /**
     * レイアウトを保存
     * PUT /api/heatmap/layouts/:hole
     * Body: レイアウトJSON
     * 
     * GCSに保存
     */
    router.put('/layouts/:hole', async (req, res) => {
        try {
            const hole = decodeURIComponent(req.params.hole);
            const layout = req.body;

            // バリデーション
            if (!layout.version || !layout.hole || !layout.grid || !Array.isArray(layout.cells)) {
                return res.status(400).json({
                    error: '無効なレイアウトデータです。version, hole, grid, cellsが必要です。'
                });
            }

            // 店舗名の整合性チェック
            if (layout.hole !== hole) {
                return res.status(400).json({
                    error: 'URLの店舗名とレイアウトデータの店舗名が一致しません'
                });
            }

            const result = await layoutStorage.saveLayout(hole, layout);

            res.json({
                success: true,
                message: 'レイアウトを保存しました（GCS）',
                ...result,
                hole,
                updated: layout.updated,
                cellCount: layout.cells.length,
            });

        } catch (error) {
            console.error('レイアウト保存中にエラーが発生しました:', error);
            res.status(500).json({
                error: 'レイアウトの保存中にエラーが発生しました',
                message: error.message,
            });
        }
    });

    return router;
};

export default createHeatmapRouter;
