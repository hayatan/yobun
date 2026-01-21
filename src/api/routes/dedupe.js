// ============================================================================
// 重複削除 ルーター
// ============================================================================
// 
// /util/dedupe/check     - BigQuery重複チェック（期間指定）
// /util/dedupe/bigquery  - BigQuery重複削除（期間指定）
// /util/dedupe/sqlite    - SQLite重複削除
// /util/dedupe/status    - 処理状態取得
// ============================================================================

import { Router } from 'express';
import stateManager from '../state-manager.js';
import { BIGQUERY } from '../../config/constants.js';

const JOB_TYPE = 'dedupe';

/**
 * 日付範囲からテーブル名リストを生成
 * @param {string} startDate - 開始日 (YYYY-MM-DD)
 * @param {string} endDate - 終了日 (YYYY-MM-DD)
 * @returns {Array<string>} テーブル名リスト
 */
const getTableNamesInRange = (startDate, endDate) => {
    const tables = [];
    const start = new Date(startDate);
    const end = new Date(endDate);
    
    for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
        const dateStr = d.toISOString().split('T')[0].replace(/-/g, '');
        tables.push(`data_${dateStr}`);
    }
    
    return tables;
};

const createDedupeRouter = (bigquery, db) => {
    const router = Router();
    const { datasetId } = BIGQUERY;
    const projectId = bigquery.projectId;

    // 処理状態を取得するエンドポイント
    router.get('/status', (req, res) => {
        res.json(stateManager.getState(JOB_TYPE));
    });

    // ============================================================================
    // BigQuery重複チェック
    // ============================================================================
    router.get('/check', async (req, res) => {
        try {
            const { startDate, endDate } = req.query;
            
            if (!startDate || !endDate) {
                return res.status(400).json({
                    error: '開始日と終了日を指定してください'
                });
            }

            const tables = getTableNamesInRange(startDate, endDate);
            const results = [];

            for (const tableName of tables) {
                try {
                    // テーブルが存在するか確認
                    const [tableExists] = await bigquery
                        .dataset(datasetId)
                        .table(tableName)
                        .exists();

                    if (!tableExists) {
                        continue;
                    }

                    // 重複チェッククエリ
                    const query = `
                        SELECT 
                            COUNT(*) as total,
                            COUNT(DISTINCT id) as unique_count
                        FROM \`${projectId}.${datasetId}.${tableName}\`
                    `;

                    const [rows] = await bigquery.query({ query });
                    const total = parseInt(rows[0].total);
                    const uniqueCount = parseInt(rows[0].unique_count);
                    const duplicateCount = total - uniqueCount;

                    if (duplicateCount > 0 || total > 0) {
                        results.push({
                            tableName,
                            total,
                            uniqueCount,
                            duplicateCount,
                            hasDuplicates: duplicateCount > 0
                        });
                    }
                } catch (error) {
                    console.error(`テーブル ${tableName} のチェック中にエラー:`, error.message);
                }
            }

            res.json({
                startDate,
                endDate,
                tablesChecked: results.length,
                results
            });
        } catch (error) {
            console.error('重複チェック中にエラーが発生しました:', error);
            res.status(500).json({ error: error.message });
        }
    });

    // ============================================================================
    // BigQuery重複削除
    // ============================================================================
    router.post('/bigquery', async (req, res) => {
        if (stateManager.isRunning(JOB_TYPE)) {
            return res.status(409).json({ 
                error: '重複削除処理は既に実行中です',
                status: stateManager.getState(JOB_TYPE)
            });
        }

        try {
            const { startDate, endDate } = req.body;
            
            if (!startDate || !endDate) {
                return res.status(400).json({
                    error: '開始日と終了日を指定してください'
                });
            }

            stateManager.startJob(JOB_TYPE);
            stateManager.updateProgress(JOB_TYPE, 0, 0, 'BigQuery重複削除を開始します...');

            // 非同期で処理を実行
            (async () => {
                try {
                    const tables = getTableNamesInRange(startDate, endDate);
                    let processed = 0;
                    let totalRemoved = 0;

                    for (const tableName of tables) {
                        try {
                            // テーブルが存在するか確認
                            const [tableExists] = await bigquery
                                .dataset(datasetId)
                                .table(tableName)
                                .exists();

                            if (!tableExists) {
                                continue;
                            }

                            stateManager.updateProgress(
                                JOB_TYPE, 
                                processed, 
                                tables.length, 
                                `${tableName} を処理中...`
                            );

                            // まず重複数を確認
                            const checkQuery = `
                                SELECT 
                                    COUNT(*) as total,
                                    COUNT(DISTINCT id) as unique_count
                                FROM \`${projectId}.${datasetId}.${tableName}\`
                            `;
                            const [checkRows] = await bigquery.query({ query: checkQuery });
                            const beforeTotal = parseInt(checkRows[0].total);
                            const uniqueCount = parseInt(checkRows[0].unique_count);

                            if (beforeTotal === uniqueCount) {
                                // 重複なし、スキップ
                                processed++;
                                continue;
                            }

                            // 重複削除クエリ（CREATE OR REPLACE TABLE）
                            const dedupeQuery = `
                                CREATE OR REPLACE TABLE \`${projectId}.${datasetId}.${tableName}\` AS
                                SELECT 
                                    id,
                                    ANY_VALUE(date) as date,
                                    ANY_VALUE(hole) as hole,
                                    ANY_VALUE(machine) as machine,
                                    ANY_VALUE(machine_number) as machine_number,
                                    ANY_VALUE(diff) as diff,
                                    ANY_VALUE(game) as game,
                                    ANY_VALUE(big) as big,
                                    ANY_VALUE(reg) as reg,
                                    ANY_VALUE(combined_rate) as combined_rate,
                                    ANY_VALUE(max_my) as max_my,
                                    ANY_VALUE(max_mdia) as max_mdia,
                                    ANY_VALUE(win) as win,
                                    ANY_VALUE(source) as source,
                                    MIN(timestamp) as timestamp
                                FROM \`${projectId}.${datasetId}.${tableName}\`
                                GROUP BY id
                            `;

                            await bigquery.query({ query: dedupeQuery });
                            
                            const removed = beforeTotal - uniqueCount;
                            totalRemoved += removed;
                            console.log(`[${tableName}] ${removed}件の重複を削除しました (${beforeTotal} → ${uniqueCount})`);

                            processed++;
                        } catch (error) {
                            console.error(`テーブル ${tableName} の重複削除中にエラー:`, error.message);
                        }
                    }

                    stateManager.updateProgress(JOB_TYPE, tables.length, tables.length, 
                        `完了: ${totalRemoved}件の重複を削除しました`);
                    stateManager.completeJob(JOB_TYPE, `完了: ${totalRemoved}件の重複を削除しました`);
                } catch (error) {
                    console.error('BigQuery重複削除中にエラーが発生しました:', error);
                    stateManager.failJob(JOB_TYPE, error.message);
                }
            })();

            res.status(202).json({ 
                message: 'BigQuery重複削除を開始しました',
                status: stateManager.getState(JOB_TYPE)
            });
        } catch (error) {
            stateManager.failJob(JOB_TYPE, error.message);
            res.status(500).json({ 
                error: 'BigQuery重複削除の開始に失敗しました',
                status: stateManager.getState(JOB_TYPE)
            });
        }
    });

    // ============================================================================
    // SQLite重複削除
    // ============================================================================
    router.post('/sqlite', async (req, res) => {
        if (stateManager.isRunning(JOB_TYPE)) {
            return res.status(409).json({ 
                error: '重複削除処理は既に実行中です',
                status: stateManager.getState(JOB_TYPE)
            });
        }

        try {
            stateManager.startJob(JOB_TYPE);
            stateManager.updateProgress(JOB_TYPE, 0, 0, 'SQLite重複チェックを開始します...');

            // 重複数を確認
            const checkResult = await new Promise((resolve, reject) => {
                db.get(`
                    SELECT 
                        COUNT(*) as total,
                        (SELECT COUNT(DISTINCT id) FROM scraped_data) as unique_count
                    FROM scraped_data
                `, (err, row) => {
                    if (err) reject(err);
                    else resolve(row);
                });
            });

            const total = checkResult.total;
            const uniqueCount = checkResult.unique_count;
            const duplicateCount = total - uniqueCount;

            if (duplicateCount === 0) {
                stateManager.updateProgress(JOB_TYPE, 1, 1, '重複データはありません');
                stateManager.completeJob(JOB_TYPE, '重複データはありません');
                return res.json({ 
                    message: '重複データはありません',
                    total,
                    uniqueCount,
                    duplicateCount: 0,
                    status: stateManager.getState(JOB_TYPE)
                });
            }

            stateManager.updateProgress(JOB_TYPE, 0, 1, `${duplicateCount}件の重複を削除中...`);

            // 重複削除
            await new Promise((resolve, reject) => {
                db.run(`
                    DELETE FROM scraped_data 
                    WHERE rowid NOT IN (
                        SELECT MIN(rowid) FROM scraped_data GROUP BY id
                    )
                `, function(err) {
                    if (err) reject(err);
                    else resolve(this.changes);
                });
            });

            stateManager.updateProgress(JOB_TYPE, 1, 1, `完了: ${duplicateCount}件の重複を削除しました`);
            stateManager.completeJob(JOB_TYPE, `完了: ${duplicateCount}件の重複を削除しました`);

            res.json({ 
                message: `${duplicateCount}件の重複を削除しました`,
                beforeTotal: total,
                afterTotal: uniqueCount,
                removed: duplicateCount,
                status: stateManager.getState(JOB_TYPE)
            });
        } catch (error) {
            console.error('SQLite重複削除中にエラーが発生しました:', error);
            stateManager.failJob(JOB_TYPE, error.message);
            res.status(500).json({ 
                error: 'SQLite重複削除中にエラーが発生しました',
                status: stateManager.getState(JOB_TYPE)
            });
        }
    });

    // ============================================================================
    // SQLite重複チェック
    // ============================================================================
    router.get('/sqlite/check', async (req, res) => {
        try {
            const result = await new Promise((resolve, reject) => {
                db.get(`
                    SELECT 
                        COUNT(*) as total,
                        (SELECT COUNT(DISTINCT id) FROM scraped_data) as unique_count
                    FROM scraped_data
                `, (err, row) => {
                    if (err) reject(err);
                    else resolve(row);
                });
            });

            const total = result.total;
            const uniqueCount = result.unique_count;
            const duplicateCount = total - uniqueCount;

            res.json({
                total,
                uniqueCount,
                duplicateCount,
                hasDuplicates: duplicateCount > 0
            });
        } catch (error) {
            console.error('SQLite重複チェック中にエラーが発生しました:', error);
            res.status(500).json({ error: error.message });
        }
    });

    return router;
};

export default createDedupeRouter;
