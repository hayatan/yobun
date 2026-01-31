// ============================================================================
// イベント DB操作
// ============================================================================
// 
// events テーブルのCRUD操作を提供
// ============================================================================

import { EVENTS_SCHEMA } from '../../../sql/events/schema.js';

/**
 * events テーブルを作成（存在しない場合）
 * @param {object} db - SQLiteデータベース接続
 * @returns {Promise<void>}
 */
const createTableIfNotExists = async (db) => {
    return new Promise((resolve, reject) => {
        db.serialize(() => {
            // テーブル作成
            db.run(EVENTS_SCHEMA.toSQLiteCreateTable(), (err) => {
                if (err) {
                    reject(err);
                    return;
                }
            });
            
            // インデックス作成
            const indexes = EVENTS_SCHEMA.toSQLiteIndexes();
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
 * イベントを追加
 * @param {object} db - SQLiteデータベース接続
 * @param {object} event - イベント情報
 * @param {string} event.date - 日付 (YYYY-MM-DD)
 * @param {string} event.hole - 店舗名
 * @param {string} event.event - イベント種類
 * @param {string} [event.description] - 説明
 * @returns {Promise<string>} 作成されたイベントのID
 */
const addEvent = async (db, event) => {
    await createTableIfNotExists(db);
    
    const id = EVENTS_SCHEMA.generateId();
    const now = new Date().toISOString();
    
    return new Promise((resolve, reject) => {
        const query = `
            INSERT INTO events (id, date, hole, event, description, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        `;
        
        db.run(query, [
            id,
            event.date,
            event.hole,
            event.event,
            event.description || null,
            now,
            now,
        ], function(err) {
            if (err) {
                console.error(`イベント追加中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(id);
            }
        });
    });
};

/**
 * イベントを一括追加
 * @param {object} db - SQLiteデータベース接続
 * @param {Array} events - イベント配列
 * @returns {Promise<number>} 追加された件数
 */
const addEventsBulk = async (db, events) => {
    await createTableIfNotExists(db);
    
    const now = new Date().toISOString();
    
    return new Promise((resolve, reject) => {
        db.serialize(() => {
            const stmt = db.prepare(`
                INSERT INTO events (id, date, hole, event, description, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            `);
            
            let count = 0;
            events.forEach(event => {
                const id = EVENTS_SCHEMA.generateId();
                stmt.run([
                    id,
                    event.date,
                    event.hole,
                    event.event,
                    event.description || null,
                    now,
                    now,
                ], function(err) {
                    if (!err) count++;
                });
            });
            
            stmt.finalize(err => {
                if (err) {
                    console.error(`イベント一括追加中にエラー: ${err.message}`);
                    reject(err);
                } else {
                    console.log(`イベントを一括追加: ${count}件`);
                    resolve(count);
                }
            });
        });
    });
};

/**
 * イベントを取得（フィルタ対応）
 * @param {object} db - SQLiteデータベース接続
 * @param {object} [filters] - フィルタ条件
 * @param {string} [filters.startDate] - 開始日
 * @param {string} [filters.endDate] - 終了日
 * @param {string} [filters.hole] - 店舗名
 * @param {string} [filters.event] - イベント種類
 * @param {number} [filters.limit] - 取得件数上限
 * @returns {Promise<Array>} イベント配列
 */
const getEvents = async (db, filters = {}) => {
    await createTableIfNotExists(db);
    
    let query = 'SELECT * FROM events WHERE 1=1';
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
    
    if (filters.event) {
        query += ' AND event = ?';
        params.push(filters.event);
    }
    
    query += ' ORDER BY date DESC, created_at DESC';
    
    if (filters.limit) {
        query += ' LIMIT ?';
        params.push(filters.limit);
    }
    
    return new Promise((resolve, reject) => {
        db.all(query, params, (err, rows) => {
            if (err) {
                console.error(`イベント取得中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(rows || []);
            }
        });
    });
};

/**
 * イベントを1件取得
 * @param {object} db - SQLiteデータベース接続
 * @param {string} id - イベントID
 * @returns {Promise<object|null>} イベント
 */
const getEventById = async (db, id) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        db.get('SELECT * FROM events WHERE id = ?', [id], (err, row) => {
            if (err) {
                console.error(`イベント取得中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(row || null);
            }
        });
    });
};

/**
 * イベントを更新
 * @param {object} db - SQLiteデータベース接続
 * @param {string} id - イベントID
 * @param {object} updates - 更新内容
 * @param {string} [updates.date] - 日付
 * @param {string} [updates.hole] - 店舗名
 * @param {string} [updates.event] - イベント種類
 * @param {string} [updates.description] - 説明
 * @returns {Promise<boolean>} 更新成功したか
 */
const updateEvent = async (db, id, updates) => {
    await createTableIfNotExists(db);
    
    const now = new Date().toISOString();
    const setClauses = [];
    const params = [];
    
    if (updates.date !== undefined) {
        setClauses.push('date = ?');
        params.push(updates.date);
    }
    
    if (updates.hole !== undefined) {
        setClauses.push('hole = ?');
        params.push(updates.hole);
    }
    
    if (updates.event !== undefined) {
        setClauses.push('event = ?');
        params.push(updates.event);
    }
    
    if (updates.description !== undefined) {
        setClauses.push('description = ?');
        params.push(updates.description);
    }
    
    setClauses.push('updated_at = ?');
    params.push(now);
    params.push(id);
    
    return new Promise((resolve, reject) => {
        const query = `UPDATE events SET ${setClauses.join(', ')} WHERE id = ?`;
        
        db.run(query, params, function(err) {
            if (err) {
                console.error(`イベント更新中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(this.changes > 0);
            }
        });
    });
};

/**
 * イベントを削除
 * @param {object} db - SQLiteデータベース接続
 * @param {string} id - イベントID
 * @returns {Promise<boolean>} 削除成功したか
 */
const deleteEvent = async (db, id) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        db.run('DELETE FROM events WHERE id = ?', [id], function(err) {
            if (err) {
                console.error(`イベント削除中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(this.changes > 0);
            }
        });
    });
};

/**
 * イベント一括削除
 * @param {object} db - SQLiteデータベース接続
 * @param {Array<string>} ids - 削除するIDの配列
 * @returns {Promise<number>} 削除件数
 */
const deleteEventsBulk = async (db, ids) => {
    await createTableIfNotExists(db);
    
    if (!ids || ids.length === 0) {
        return 0;
    }
    
    const placeholders = ids.map(() => '?').join(',');
    
    return new Promise((resolve, reject) => {
        db.run(`DELETE FROM events WHERE id IN (${placeholders})`, ids, function(err) {
            if (err) {
                console.error(`イベント一括削除中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(this.changes);
            }
        });
    });
};

/**
 * 全イベントを取得（BigQuery同期用）
 * @param {object} db - SQLiteデータベース接続
 * @returns {Promise<Array>} 全イベント配列
 */
const getAllEvents = async (db) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        db.all('SELECT * FROM events ORDER BY date DESC', [], (err, rows) => {
            if (err) {
                console.error(`全イベント取得中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(rows || []);
            }
        });
    });
};

/**
 * イベント種類の一覧を取得
 * @param {object} db - SQLiteデータベース接続
 * @returns {Promise<Array<string>>} イベント種類配列
 */
const getDistinctEventTypes = async (db) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        db.all('SELECT DISTINCT event FROM events ORDER BY event', [], (err, rows) => {
            if (err) {
                console.error(`イベント種類取得中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve((rows || []).map(row => row.event));
            }
        });
    });
};

/**
 * 店舗の一覧を取得
 * @param {object} db - SQLiteデータベース接続
 * @returns {Promise<Array<string>>} 店舗名配列
 */
const getDistinctHoles = async (db) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        db.all('SELECT DISTINCT hole FROM events ORDER BY hole', [], (err, rows) => {
            if (err) {
                console.error(`店舗一覧取得中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve((rows || []).map(row => row.hole));
            }
        });
    });
};

const events = {
    createTableIfNotExists,
    addEvent,
    addEventsBulk,
    getEvents,
    getEventById,
    updateEvent,
    deleteEvent,
    deleteEventsBulk,
    getAllEvents,
    getDistinctEventTypes,
    getDistinctHoles,
    // スキーマのユーティリティをエクスポート
    generateId: EVENTS_SCHEMA.generateId.bind(EVENTS_SCHEMA),
};

export default events;
