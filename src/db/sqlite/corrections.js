// ============================================================================
// 手動補正データ DB操作
// ============================================================================
// 
// manual_corrections テーブルのCRUD操作を提供
// 強制再取得時のフォールバック機能も含む
// ============================================================================

import { MANUAL_CORRECTIONS_SCHEMA } from '../../../sql/manual_corrections/schema.js';

/**
 * manual_corrections テーブルを作成（存在しない場合）
 * @param {object} db - SQLiteデータベース接続
 * @returns {Promise<void>}
 */
const createTableIfNotExists = async (db) => {
    return new Promise((resolve, reject) => {
        db.serialize(() => {
            // テーブル作成
            db.run(MANUAL_CORRECTIONS_SCHEMA.toSQLiteCreateTable(), (err) => {
                if (err) {
                    reject(err);
                    return;
                }
            });
            
            // インデックス作成
            const indexes = MANUAL_CORRECTIONS_SCHEMA.toSQLiteIndexes();
            indexes.forEach((indexSql) => {
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
 * 手動補正データを一括追加
 * @param {object} db - SQLiteデータベース接続
 * @param {object} params - パラメータ
 * @param {string} params.date - 日付
 * @param {string} params.hole - 店舗名
 * @param {string} params.machine - 機種名
 * @param {string} [params.failureId] - 元の失敗レコードID
 * @param {string} [params.notes] - メモ
 * @param {Array} params.data - データ配列
 * @param {string} [params.source='slorepo'] - データソース
 * @returns {Promise<number>} 追加された件数
 */
const addCorrections = async (db, params) => {
    await createTableIfNotExists(db);
    
    const { date, hole, machine, failureId, notes, data, source = 'slorepo' } = params;
    const now = new Date().toISOString();
    
    return new Promise((resolve, reject) => {
        db.serialize(() => {
            const stmt = db.prepare(`
                INSERT OR REPLACE INTO manual_corrections (
                    id, date, hole, machine, machine_number,
                    diff, game, big, reg, combined_rate,
                    max_my, max_mdia, win, source, timestamp,
                    failure_id, corrected_at, notes
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            `);
            
            let count = 0;
            data.forEach(row => {
                const id = MANUAL_CORRECTIONS_SCHEMA.generateId(date, hole, row.machineNumber, source);
                const win = row.diff > 0 ? 1 : 0;
                
                stmt.run([
                    id,
                    date,
                    hole,
                    machine,
                    row.machineNumber,
                    row.diff,
                    row.game,
                    row.big,
                    row.reg,
                    row.combinedRate,
                    0, // max_my
                    0, // max_mdia
                    win,
                    source,
                    now,
                    failureId || null,
                    now,
                    notes || null,
                ], function(err) {
                    if (!err) count++;
                });
            });
            
            stmt.finalize(err => {
                if (err) {
                    console.error(`手動補正データ追加中にエラー: ${err.message}`);
                    reject(err);
                } else {
                    console.log(`[${date}][${hole}][${machine}] 手動補正データを追加: ${count}件`);
                    resolve(count);
                }
            });
        });
    });
};

/**
 * 手動補正データを scraped_data にコピー
 * @param {object} db - SQLiteデータベース接続
 * @param {string} date - 日付
 * @param {string} hole - 店舗名
 * @param {string} [machine] - 機種名（指定しない場合は全機種）
 * @returns {Promise<number>} コピーされた件数
 */
const copyToScrapedData = async (db, date, hole, machine = null) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        let query = `
            INSERT OR REPLACE INTO scraped_data (
                id, date, hole, machine, machine_number,
                diff, game, big, reg, combined_rate,
                max_my, max_mdia, win, source, timestamp
            )
            SELECT 
                id, date, hole, machine, machine_number,
                diff, game, big, reg, combined_rate,
                max_my, max_mdia, win, source, timestamp
            FROM manual_corrections
            WHERE date = ? AND hole = ?
        `;
        const params = [date, hole];
        
        if (machine) {
            query += ' AND machine = ?';
            params.push(machine);
        }
        
        db.run(query, params, function(err) {
            if (err) {
                console.error(`scraped_dataへのコピー中にエラー: ${err.message}`);
                reject(err);
            } else {
                console.log(`[${date}][${hole}] scraped_dataにコピー: ${this.changes}件`);
                resolve(this.changes);
            }
        });
    });
};

/**
 * 手動補正データを取得（フィルタ対応）
 * @param {object} db - SQLiteデータベース接続
 * @param {object} [filters] - フィルタ条件
 * @param {string} [filters.startDate] - 開始日
 * @param {string} [filters.endDate] - 終了日
 * @param {string} [filters.hole] - 店舗名
 * @param {string} [filters.machine] - 機種名
 * @param {number} [filters.limit] - 取得件数上限
 * @returns {Promise<Array>} 補正データ配列
 */
const getCorrections = async (db, filters = {}) => {
    await createTableIfNotExists(db);
    
    let query = 'SELECT * FROM manual_corrections WHERE 1=1';
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
    
    if (filters.machine) {
        query += ' AND machine = ?';
        params.push(filters.machine);
    }
    
    query += ' ORDER BY date DESC, corrected_at DESC';
    
    if (filters.limit) {
        query += ' LIMIT ?';
        params.push(filters.limit);
    }
    
    return new Promise((resolve, reject) => {
        db.all(query, params, (err, rows) => {
            if (err) {
                console.error(`補正データ取得中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(rows || []);
            }
        });
    });
};

/**
 * 特定日付・店舗の補正データが存在するか確認
 * @param {object} db - SQLiteデータベース接続
 * @param {string} date - 日付
 * @param {string} hole - 店舗名
 * @returns {Promise<boolean>} 存在するか
 */
const hasCorrections = async (db, date, hole) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        const query = `
            SELECT COUNT(*) as count FROM manual_corrections 
            WHERE date = ? AND hole = ?
        `;
        db.get(query, [date, hole], (err, row) => {
            if (err) {
                reject(err);
            } else {
                resolve((row?.count || 0) > 0);
            }
        });
    });
};

/**
 * フォールバック: 手動補正データから scraped_data を復元
 * 強制再取得でスクレイピングが失敗した場合に使用
 * @param {object} db - SQLiteデータベース接続
 * @param {string} date - 日付
 * @param {string} hole - 店舗名
 * @returns {Promise<{restored: boolean, count: number}>} 復元結果
 */
const restoreFromCorrections = async (db, date, hole) => {
    const hasData = await hasCorrections(db, date, hole);
    
    if (!hasData) {
        return { restored: false, count: 0 };
    }
    
    const count = await copyToScrapedData(db, date, hole);
    console.log(`[${date}][${hole}] フォールバック: 手動補正データから ${count}件 を復元`);
    
    return { restored: true, count };
};

/**
 * 補正データを削除
 * @param {object} db - SQLiteデータベース接続
 * @param {string} id - 補正データID
 * @returns {Promise<boolean>} 削除成功したか
 */
const deleteCorrection = async (db, id) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        db.run('DELETE FROM manual_corrections WHERE id = ?', [id], function(err) {
            if (err) {
                console.error(`補正データ削除中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(this.changes > 0);
            }
        });
    });
};

/**
 * 日付・店舗・機種で補正データを一括削除
 * @param {object} db - SQLiteデータベース接続
 * @param {string} date - 日付
 * @param {string} hole - 店舗名
 * @param {string} [machine] - 機種名（指定しない場合は全機種）
 * @returns {Promise<number>} 削除された件数
 */
const deleteCorrections = async (db, date, hole, machine = null) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        let query = 'DELETE FROM manual_corrections WHERE date = ? AND hole = ?';
        const params = [date, hole];
        
        if (machine) {
            query += ' AND machine = ?';
            params.push(machine);
        }
        
        db.run(query, params, function(err) {
            if (err) {
                console.error(`補正データ一括削除中にエラー: ${err.message}`);
                reject(err);
            } else {
                console.log(`[${date}][${hole}] 補正データを削除: ${this.changes}件`);
                resolve(this.changes);
            }
        });
    });
};

/**
 * 補正データのサマリーを取得（機種単位でグループ化）
 * @param {object} db - SQLiteデータベース接続
 * @param {object} [filters] - フィルタ条件
 * @returns {Promise<Array>} サマリー配列
 */
const getCorrectionsSummary = async (db, filters = {}) => {
    await createTableIfNotExists(db);
    
    let query = `
        SELECT 
            date, hole, machine, 
            COUNT(*) as count,
            MIN(corrected_at) as first_corrected,
            MAX(corrected_at) as last_corrected,
            failure_id, notes
        FROM manual_corrections
        WHERE 1=1
    `;
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
    
    query += ' GROUP BY date, hole, machine ORDER BY date DESC, hole, machine';
    
    return new Promise((resolve, reject) => {
        db.all(query, params, (err, rows) => {
            if (err) {
                console.error(`補正サマリー取得中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(rows || []);
            }
        });
    });
};

const corrections = {
    createTableIfNotExists,
    addCorrections,
    copyToScrapedData,
    getCorrections,
    hasCorrections,
    restoreFromCorrections,
    deleteCorrection,
    deleteCorrections,
    getCorrectionsSummary,
    // スキーマのユーティリティをエクスポート
    generateId: MANUAL_CORRECTIONS_SCHEMA.generateId.bind(MANUAL_CORRECTIONS_SCHEMA),
};

export default corrections;
