// ============================================================================
// ヒートマップ ルーター
// ============================================================================
//
// /api/heatmap/data - 台別統計データを取得（BigQuery machine_stats）
// /api/heatmap/holes - 店舗一覧（slorepo-config）
// /api/heatmap/layouts - レイアウト一覧（hole + floor 付き）
// /api/heatmap/layouts/:hole - 特定店舗のフロア一覧
// /api/heatmap/layouts/:hole/:floor - レイアウト取得/保存/作成/削除
//
// ストレージ: GCS のみ（layouts/{hole-slug}/{floor-slug}.json）
// ============================================================================

import { Router } from 'express';
import layoutStorage from '../../config/heatmap-layouts/storage.js';
import slorepoConfig from '../../config/slorepo-config.js';

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
     * 店舗一覧を取得（レイアウト新規作成時の店舗選択用）
     * GET /api/heatmap/holes
     */
    router.get('/holes', async (req, res) => {
        try {
            const holes = (slorepoConfig.holes || []).map((h) => h.name);
            res.json({ holes });
        } catch (error) {
            console.error('店舗一覧取得中にエラーが発生しました:', error);
            res.status(500).json({
                error: '店舗一覧の取得中にエラーが発生しました',
                message: error.message,
            });
        }
    });

    /**
     * レイアウト一覧を取得（GCSのみ、各要素に floor を含む）
     * GET /api/heatmap/layouts
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
     * 特定店舗のフロア一覧を取得
     * GET /api/heatmap/layouts/:hole
     */
    router.get('/layouts/:hole', async (req, res) => {
        try {
            const hole = decodeURIComponent(req.params.hole);
            const floors = await layoutStorage.listFloors(hole);
            res.json({ hole, floors });
        } catch (error) {
            console.error('フロア一覧取得中にエラーが発生しました:', error);
            res.status(500).json({
                error: 'フロア一覧の取得中にエラーが発生しました',
                message: error.message,
            });
        }
    });

    /**
     * 特定店舗・フロアのレイアウトを取得
     * GET /api/heatmap/layouts/:hole/:floor
     */
    router.get('/layouts/:hole/:floor', async (req, res) => {
        try {
            const hole = decodeURIComponent(req.params.hole);
            const floor = decodeURIComponent(req.params.floor);
            const { layout } = await layoutStorage.loadLayout(hole, floor);

            if (!layout) {
                return res.status(404).json({
                    error: `店舗「${hole}」のフロア「${floor}」のレイアウトが見つかりません`,
                });
            }

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
     * PUT /api/heatmap/layouts/:hole/:floor
     * Body: レイアウトJSON
     */
    router.put('/layouts/:hole/:floor', async (req, res) => {
        try {
            const hole = decodeURIComponent(req.params.hole);
            const floor = decodeURIComponent(req.params.floor);
            const layout = req.body;

            if (!layout.version || !layout.hole || !layout.grid || !Array.isArray(layout.cells)) {
                return res.status(400).json({
                    error: '無効なレイアウトデータです。version, hole, grid, cellsが必要です。',
                });
            }
            if (layout.hole !== hole) {
                return res.status(400).json({
                    error: 'URLの店舗名とレイアウトデータの店舗名が一致しません',
                });
            }
            if (layout.floor !== floor) {
                return res.status(400).json({
                    error: 'URLのフロア名とレイアウトデータのフロア名が一致しません',
                });
            }

            const result = await layoutStorage.saveLayout(hole, floor, layout);

            res.json({
                success: true,
                message: 'レイアウトを保存しました',
                ...result,
                hole,
                floor,
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

    /**
     * 新規レイアウト作成（空テンプレートをGCSに保存）
     * POST /api/heatmap/layouts/:hole/:floor
     * Body: { rows?, cols? } 省略時は 30x30
     */
    router.post('/layouts/:hole/:floor', async (req, res) => {
        try {
            const hole = decodeURIComponent(req.params.hole);
            const floor = decodeURIComponent(req.params.floor);
            const { rows = 30, cols = 30 } = req.body || {};

            const exists = await layoutStorage.layoutExists(hole, floor);
            if (exists) {
                return res.status(409).json({
                    error: `店舗「${hole}」のフロア「${floor}」のレイアウトは既に存在します`,
                });
            }

            const layout = {
                version: '2.0',
                hole,
                floor,
                updated: new Date().toISOString().split('T')[0],
                description: '',
                grid: { rows: Number(rows) || 30, cols: Number(cols) || 30 },
                walls: [],
                cells: [],
            };

            await layoutStorage.saveLayout(hole, floor, layout);

            res.status(201).json({
                success: true,
                message: 'レイアウトを作成しました',
                hole,
                floor,
                layout,
            });
        } catch (error) {
            console.error('レイアウト作成中にエラーが発生しました:', error);
            res.status(500).json({
                error: 'レイアウトの作成中にエラーが発生しました',
                message: error.message,
            });
        }
    });

    /**
     * レイアウトを削除
     * DELETE /api/heatmap/layouts/:hole/:floor
     */
    router.delete('/layouts/:hole/:floor', async (req, res) => {
        try {
            const hole = decodeURIComponent(req.params.hole);
            const floor = decodeURIComponent(req.params.floor);
            const result = await layoutStorage.deleteLayout(hole, floor);

            if (!result.success) {
                return res.status(404).json({ error: result.error || 'レイアウトが存在しません' });
            }

            res.json({ success: true, message: 'レイアウトを削除しました', hole, floor });
        } catch (error) {
            console.error('レイアウト削除中にエラーが発生しました:', error);
            res.status(500).json({
                error: 'レイアウトの削除中にエラーが発生しました',
                message: error.message,
            });
        }
    });

    return router;
};

export default createHeatmapRouter;
