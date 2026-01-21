// ============================================================================
// スクレイピング失敗記録 DB操作
// ============================================================================
// 
// scrape_failures テーブルのCRUD操作を提供
// ============================================================================

import { SCRAPE_FAILURES_SCHEMA } from '../../../sql/scrape_failures/schema.js';

/**
 * scrape_failures テーブルを作成（存在しない場合）
 * @param {object} db - SQLiteデータベース接続
 * @returns {Promise<void>}
 */
const createTableIfNotExists = async (db) => {
    return new Promise((resolve, reject) => {
        db.serialize(() => {
            // テーブル作成
            db.run(SCRAPE_FAILURES_SCHEMA.toSQLiteCreateTable(), (err) => {
                if (err) {
                    reject(err);
                    return;
                }
            });
            
            // インデックス作成
            const indexes = SCRAPE_FAILURES_SCHEMA.toSQLiteIndexes();
            indexes.forEach((indexSql, i) => {
                db.run(indexSql, (err) => {
                    if (err && !err.message.includes('already exists')) {
                        console.error(`インデックス作成エラー: ${err.message}`);
                    }
                });
            });
            
            resolve();
        });
    });
};

/**
 * 失敗レコードを追加（同じ日付・店舗・機種のpendingレコードがあれば上書き）
 * @param {object} db - SQLiteデータベース接続
 * @param {object} failure - 失敗情報
 * @param {string} failure.date - 対象日付
 * @param {string} failure.hole - 店舗名
 * @param {string} failure.holeCode - 店舗コード
 * @param {string} [failure.machine] - 機種名
 * @param {string} [failure.machineUrl] - 機種ページURL
 * @param {string} failure.errorType - エラー種別
 * @param {string} [failure.errorMessage] - エラー詳細
 * @returns {Promise<string>} 作成または更新されたレコードのID
 */
const addFailure = async (db, failure) => {
    await createTableIfNotExists(db);
    
    const now = new Date().toISOString();
    const machine = failure.machine || null;
    
    // 同じ日付・店舗・機種のpendingレコードを検索
    const existing = await new Promise((resolve, reject) => {
        const query = `
            SELECT id FROM scrape_failures 
            WHERE date = ? AND hole = ? AND (machine = ? OR (machine IS NULL AND ? IS NULL))
            AND status = 'pending'
        `;
        db.get(query, [failure.date, failure.hole, machine, machine], (err, row) => {
            if (err) reject(err);
            else resolve(row);
        });
    });
    
    if (existing) {
        // 既存レコードを更新
        return new Promise((resolve, reject) => {
            const query = `
                UPDATE scrape_failures SET
                    hole_code = ?,
                    machine_url = ?,
                    error_type = ?,
                    error_message = ?,
                    failed_at = ?
                WHERE id = ?
            `;
            
            db.run(query, [
                failure.holeCode,
                failure.machineUrl || null,
                failure.errorType,
                failure.errorMessage || null,
                now,
                existing.id,
            ], function(err) {
                if (err) {
                    console.error(`[${failure.date}][${failure.hole}] 失敗記録の更新中にエラー: ${err.message}`);
                    reject(err);
                } else {
                    console.log(`[${failure.date}][${failure.hole}] 失敗記録を更新: ${existing.id}`);
                    resolve(existing.id);
                }
            });
        });
    } else {
        // 新規レコードを作成
        const id = SCRAPE_FAILURES_SCHEMA.generateId();
        return new Promise((resolve, reject) => {
            const query = `
                INSERT INTO scrape_failures (
                    id, date, hole, hole_code, machine, machine_url,
                    error_type, error_message, failed_at, status
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            `;
            
            db.run(query, [
                id,
                failure.date,
                failure.hole,
                failure.holeCode,
                machine,
                failure.machineUrl || null,
                failure.errorType,
                failure.errorMessage || null,
                now,
                SCRAPE_FAILURES_SCHEMA.statuses.PENDING,
            ], function(err) {
                if (err) {
                    console.error(`[${failure.date}][${failure.hole}] 失敗記録の追加中にエラー: ${err.message}`);
                    reject(err);
                } else {
                    console.log(`[${failure.date}][${failure.hole}] 失敗記録を追加: ${id}`);
                    resolve(id);
                }
            });
        });
    }
};

/**
 * 失敗レコードを取得（フィルタ対応）
 * @param {object} db - SQLiteデータベース接続
 * @param {object} [filters] - フィルタ条件
 * @param {string} [filters.startDate] - 開始日
 * @param {string} [filters.endDate] - 終了日
 * @param {string} [filters.hole] - 店舗名
 * @param {string} [filters.status] - ステータス
 * @param {number} [filters.limit] - 取得件数上限
 * @returns {Promise<Array>} 失敗レコード配列
 */
const getFailures = async (db, filters = {}) => {
    await createTableIfNotExists(db);
    
    let query = 'SELECT * FROM scrape_failures WHERE 1=1';
    const params = [];
    
    if (filters.startDate) {
        query += ' AND date >= ?';
        params.push(filters.startDate);
    }
    
    if (filters.endDate) {
        query += ' AND date <= ?';
        params.push(filters.endDate);
    }
    
    if (filters.hole) {
        query += ' AND hole = ?';
        params.push(filters.hole);
    }
    
    if (filters.status) {
        query += ' AND status = ?';
        params.push(filters.status);
    }
    
    query += ' ORDER BY date DESC, failed_at DESC';
    
    if (filters.limit) {
        query += ' LIMIT ?';
        params.push(filters.limit);
    }
    
    return new Promise((resolve, reject) => {
        db.all(query, params, (err, rows) => {
            if (err) {
                console.error(`失敗レコード取得中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(rows || []);
            }
        });
    });
};

/**
 * 失敗レコードを1件取得
 * @param {object} db - SQLiteデータベース接続
 * @param {string} id - 失敗レコードID
 * @returns {Promise<object|null>} 失敗レコード
 */
const getFailureById = async (db, id) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        db.get('SELECT * FROM scrape_failures WHERE id = ?', [id], (err, row) => {
            if (err) {
                console.error(`失敗レコード取得中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(row || null);
            }
        });
    });
};

/**
 * 失敗レコードのステータスを更新
 * @param {object} db - SQLiteデータベース接続
 * @param {string} id - 失敗レコードID
 * @param {string} status - 新しいステータス
 * @param {string} [resolvedMethod] - 解決方法（resolved時）
 * @returns {Promise<boolean>} 更新成功したか
 */
const updateFailureStatus = async (db, id, status, resolvedMethod = null) => {
    await createTableIfNotExists(db);
    
    const now = new Date().toISOString();
    
    return new Promise((resolve, reject) => {
        let query;
        let params;
        
        if (status === SCRAPE_FAILURES_SCHEMA.statuses.RESOLVED) {
            query = `
                UPDATE scrape_failures 
                SET status = ?, resolved_at = ?, resolved_method = ?
                WHERE id = ?
            `;
            params = [status, now, resolvedMethod, id];
        } else {
            query = `
                UPDATE scrape_failures 
                SET status = ?
                WHERE id = ?
            `;
            params = [status, id];
        }
        
        db.run(query, params, function(err) {
            if (err) {
                console.error(`失敗レコードステータス更新中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(this.changes > 0);
            }
        });
    });
};

/**
 * 失敗レコードを削除
 * @param {object} db - SQLiteデータベース接続
 * @param {string} id - 失敗レコードID
 * @returns {Promise<boolean>} 削除成功したか
 */
const deleteFailure = async (db, id) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        db.run('DELETE FROM scrape_failures WHERE id = ?', [id], function(err) {
            if (err) {
                console.error(`失敗レコード削除中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(this.changes > 0);
            }
        });
    });
};

/**
 * 特定日付・店舗の未解決失敗レコード数を取得
 * @param {object} db - SQLiteデータベース接続
 * @param {string} date - 日付
 * @param {string} hole - 店舗名
 * @returns {Promise<number>} 未解決件数
 */
const getPendingCount = async (db, date, hole) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        const query = `
            SELECT COUNT(*) as count FROM scrape_failures 
            WHERE date = ? AND hole = ? AND status = ?
        `;
        db.get(query, [date, hole, SCRAPE_FAILURES_SCHEMA.statuses.PENDING], (err, row) => {
            if (err) {
                reject(err);
            } else {
                resolve(row?.count || 0);
            }
        });
    });
};

/**
 * 統計情報を取得
 * @param {object} db - SQLiteデータベース接続
 * @returns {Promise<object>} 統計情報
 */
const getStats = async (db) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        const query = `
            SELECT 
                status,
                COUNT(*) as count
            FROM scrape_failures
            GROUP BY status
        `;
        db.all(query, [], (err, rows) => {
            if (err) {
                reject(err);
            } else {
                const stats = {
                    pending: 0,
                    resolved: 0,
                    ignored: 0,
                    total: 0,
                };
                rows.forEach(row => {
                    stats[row.status] = row.count;
                    stats.total += row.count;
                });
                resolve(stats);
            }
        });
    });
};

/**
 * 失敗レコード一括削除
 * @param {Object} db - SQLiteデータベース接続
 * @param {Array<string>} ids - 削除するIDの配列
 * @returns {Promise<number>} 削除件数
 */
const deleteFailuresBulk = async (db, ids) => {
    await createTableIfNotExists(db);
    
    if (!ids || ids.length === 0) {
        return 0;
    }
    
    const placeholders = ids.map(() => '?').join(',');
    
    return new Promise((resolve, reject) => {
        db.run(`DELETE FROM scrape_failures WHERE id IN (${placeholders})`, ids, function(err) {
            if (err) {
                console.error(`失敗レコード一括削除中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(this.changes);
            }
        });
    });
};

const failures = {
    createTableIfNotExists,
    addFailure,
    getFailures,
    getFailureById,
    updateFailureStatus,
    deleteFailure,
    deleteFailuresBulk,
    getPendingCount,
    getStats,
    // スキーマの定数をエクスポート
    errorTypes: SCRAPE_FAILURES_SCHEMA.errorTypes,
    statuses: SCRAPE_FAILURES_SCHEMA.statuses,
    resolvedMethods: SCRAPE_FAILURES_SCHEMA.resolvedMethods,
};

export default failures;
