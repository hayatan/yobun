// ============================================================================
// ヒートマップ ルーター
// ============================================================================
// 
// /api/heatmap/data - 台別統計データを取得（BigQuery machine_stats）
// /api/heatmap/layouts - レイアウト一覧を取得
// /api/heatmap/layouts/:hole - 特定店舗のレイアウトを取得/保存
// ============================================================================

import { Router } from 'express';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// レイアウトファイルのディレクトリ
const LAYOUTS_DIR = path.join(__dirname, '../../config/heatmap-layouts');

/**
 * 店舗名からファイル名を生成
 */
const holeToFilename = (hole) => {
    const mapping = {
        'アイランド秋葉原店': 'island-akihabara.json',
        'エスパス秋葉原駅前店': 'espace-akihabara.json',
        'ビッグアップル秋葉原店': 'bigapple-akihabara.json',
        '秋葉原UNO': 'uno-akihabara.json',
        'エスパス上野本館': 'espace-ueno.json',
        '三ノ輪ＵＮＯ': 'uno-minowa.json',
        'マルハン新宿東宝ビル店': 'maruhan-shinjuku.json',
        'マルハン鹿浜店': 'maruhan-shikahama.json',
        'ジュラク王子店': 'juraku-oji.json',
        'メッセ竹の塚': 'messe-takenotsuka.json',
        'ニュークラウン綾瀬店': 'newcrown-ayase.json',
        'タイヨーネオ富山店': 'taiyoneo-toyama.json',
        'KEIZ富山田中店': 'keiz-toyama.json',
    };
    return mapping[hole] || `${hole.replace(/[^a-zA-Z0-9]/g, '-').toLowerCase()}.json`;
};

/**
 * ファイル名から店舗名を逆引き
 */
const filenameToHole = (filename) => {
    const mapping = {
        'island-akihabara.json': 'アイランド秋葉原店',
        'espace-akihabara.json': 'エスパス秋葉原駅前店',
        'bigapple-akihabara.json': 'ビッグアップル秋葉原店',
        'uno-akihabara.json': '秋葉原UNO',
        'espace-ueno.json': 'エスパス上野本館',
        'uno-minowa.json': '三ノ輪ＵＮＯ',
        'maruhan-shinjuku.json': 'マルハン新宿東宝ビル店',
        'maruhan-shikahama.json': 'マルハン鹿浜店',
        'juraku-oji.json': 'ジュラク王子店',
        'messe-takenotsuka.json': 'メッセ竹の塚',
        'newcrown-ayase.json': 'ニュークラウン綾瀬店',
        'taiyoneo-toyama.json': 'タイヨーネオ富山店',
        'keiz-toyama.json': 'KEIZ富山田中店',
    };
    return mapping[filename] || null;
};

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
     */
    router.get('/layouts', async (req, res) => {
        try {
            const files = await fs.readdir(LAYOUTS_DIR);
            const layouts = [];

            for (const file of files) {
                if (file.endsWith('.json') && !file.startsWith('_')) {
                    try {
                        const filePath = path.join(LAYOUTS_DIR, file);
                        const content = await fs.readFile(filePath, 'utf-8');
                        const layout = JSON.parse(content);
                        layouts.push({
                            filename: file,
                            hole: layout.hole,
                            version: layout.version,
                            updated: layout.updated,
                            description: layout.description,
                            cellCount: layout.cells?.length || 0,
                        });
                    } catch (e) {
                        console.warn(`レイアウトファイル読み込みエラー: ${file}`, e.message);
                    }
                }
            }

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
     */
    router.get('/layouts/:hole', async (req, res) => {
        try {
            const hole = decodeURIComponent(req.params.hole);
            const filename = holeToFilename(hole);
            const filePath = path.join(LAYOUTS_DIR, filename);

            try {
                const content = await fs.readFile(filePath, 'utf-8');
                const layout = JSON.parse(content);
                res.json(layout);
            } catch (e) {
                if (e.code === 'ENOENT') {
                    return res.status(404).json({
                        error: `店舗「${hole}」のレイアウトが見つかりません`,
                        filename,
                    });
                }
                throw e;
            }

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

            // 更新日時を設定
            layout.updated = new Date().toISOString().split('T')[0];

            const filename = holeToFilename(hole);
            const filePath = path.join(LAYOUTS_DIR, filename);

            await fs.writeFile(filePath, JSON.stringify(layout, null, 2), 'utf-8');

            res.json({
                success: true,
                message: 'レイアウトを保存しました',
                filename,
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
