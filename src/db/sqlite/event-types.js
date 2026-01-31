// ============================================================================
// イベントタイプ DB操作
// ============================================================================
// 
// event_types テーブルのCRUD操作を提供
// フロントエンドの選択肢表示に使用
// ============================================================================

import { EVENT_TYPES_SCHEMA } from '../../../sql/event_types/schema.js';

/**
 * event_types テーブルを作成（存在しない場合）
 * @param {object} db - SQLiteデータベース接続
 * @returns {Promise<void>}
 */
const createTableIfNotExists = async (db) => {
    return new Promise((resolve, reject) => {
        db.serialize(() => {
            // テーブル作成
            db.run(EVENT_TYPES_SCHEMA.toSQLiteCreateTable(), (err) => {
                if (err) {
                    reject(err);
                    return;
                }
            });
            
            // インデックス作成
            const indexes = EVENT_TYPES_SCHEMA.toSQLiteIndexes();
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
 * イベントタイプを追加
 * @param {object} db - SQLiteデータベース接続
 * @param {object} eventType - イベントタイプ情報
 * @param {string} eventType.name - イベント名
 * @param {number} [eventType.sortOrder=0] - 表示順
 * @returns {Promise<string>} 作成されたイベントタイプのID
 */
const addEventType = async (db, eventType) => {
    await createTableIfNotExists(db);
    
    const id = EVENT_TYPES_SCHEMA.generateId();
    const now = new Date().toISOString();
    
    return new Promise((resolve, reject) => {
        const query = `
            INSERT INTO event_types (id, name, sort_order, created_at)
            VALUES (?, ?, ?, ?)
        `;
        
        db.run(query, [
            id,
            eventType.name,
            eventType.sortOrder || 0,
            now,
        ], function(err) {
            if (err) {
                if (err.message.includes('UNIQUE constraint failed')) {
                    reject(new Error(`イベントタイプ "${eventType.name}" は既に存在します`));
                } else {
                    console.error(`イベントタイプ追加中にエラー: ${err.message}`);
                    reject(err);
                }
            } else {
                resolve(id);
            }
        });
    });
};

/**
 * イベントタイプを取得（表示順でソート）
 * @param {object} db - SQLiteデータベース接続
 * @returns {Promise<Array>} イベントタイプ配列
 */
const getEventTypes = async (db) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        db.all('SELECT * FROM event_types ORDER BY sort_order ASC, name ASC', [], (err, rows) => {
            if (err) {
                console.error(`イベントタイプ取得中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(rows || []);
            }
        });
    });
};

/**
 * イベントタイプを1件取得
 * @param {object} db - SQLiteデータベース接続
 * @param {string} id - イベントタイプID
 * @returns {Promise<object|null>} イベントタイプ
 */
const getEventTypeById = async (db, id) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        db.get('SELECT * FROM event_types WHERE id = ?', [id], (err, row) => {
            if (err) {
                console.error(`イベントタイプ取得中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(row || null);
            }
        });
    });
};

/**
 * イベントタイプを名前で取得
 * @param {object} db - SQLiteデータベース接続
 * @param {string} name - イベント名
 * @returns {Promise<object|null>} イベントタイプ
 */
const getEventTypeByName = async (db, name) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        db.get('SELECT * FROM event_types WHERE name = ?', [name], (err, row) => {
            if (err) {
                console.error(`イベントタイプ取得中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(row || null);
            }
        });
    });
};

/**
 * イベントタイプを更新
 * @param {object} db - SQLiteデータベース接続
 * @param {string} id - イベントタイプID
 * @param {object} updates - 更新内容
 * @param {string} [updates.name] - イベント名
 * @param {number} [updates.sortOrder] - 表示順
 * @returns {Promise<boolean>} 更新成功したか
 */
const updateEventType = async (db, id, updates) => {
    await createTableIfNotExists(db);
    
    const setClauses = [];
    const params = [];
    
    if (updates.name !== undefined) {
        setClauses.push('name = ?');
        params.push(updates.name);
    }
    
    if (updates.sortOrder !== undefined) {
        setClauses.push('sort_order = ?');
        params.push(updates.sortOrder);
    }
    
    if (setClauses.length === 0) {
        return false;
    }
    
    params.push(id);
    
    return new Promise((resolve, reject) => {
        const query = `UPDATE event_types SET ${setClauses.join(', ')} WHERE id = ?`;
        
        db.run(query, params, function(err) {
            if (err) {
                if (err.message.includes('UNIQUE constraint failed')) {
                    reject(new Error(`イベントタイプ "${updates.name}" は既に存在します`));
                } else {
                    console.error(`イベントタイプ更新中にエラー: ${err.message}`);
                    reject(err);
                }
            } else {
                resolve(this.changes > 0);
            }
        });
    });
};

/**
 * イベントタイプを削除
 * @param {object} db - SQLiteデータベース接続
 * @param {string} id - イベントタイプID
 * @returns {Promise<boolean>} 削除成功したか
 */
const deleteEventType = async (db, id) => {
    await createTableIfNotExists(db);
    
    return new Promise((resolve, reject) => {
        db.run('DELETE FROM event_types WHERE id = ?', [id], function(err) {
            if (err) {
                console.error(`イベントタイプ削除中にエラー: ${err.message}`);
                reject(err);
            } else {
                resolve(this.changes > 0);
            }
        });
    });
};

/**
 * 初期データを投入（存在しない場合のみ）
 * @param {object} db - SQLiteデータベース接続
 * @param {Array<{name: string, sortOrder?: number}>} initialTypes - 初期イベントタイプ
 * @returns {Promise<number>} 追加された件数
 */
const seedEventTypes = async (db, initialTypes) => {
    await createTableIfNotExists(db);
    
    let added = 0;
    
    for (const eventType of initialTypes) {
        const existing = await getEventTypeByName(db, eventType.name);
        if (!existing) {
            try {
                await addEventType(db, eventType);
                added++;
            } catch (err) {
                // 重複エラーは無視
                if (!err.message.includes('既に存在します')) {
                    throw err;
                }
            }
        }
    }
    
    return added;
};

const eventTypes = {
    createTableIfNotExists,
    addEventType,
    getEventTypes,
    getEventTypeById,
    getEventTypeByName,
    updateEventType,
    deleteEventType,
    seedEventTypes,
    // スキーマのユーティリティをエクスポート
    generateId: EVENT_TYPES_SCHEMA.generateId.bind(EVENT_TYPES_SCHEMA),
};

export default eventTypes;
