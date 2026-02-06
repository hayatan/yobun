import util from '../../util/common.js';

// テーブル作成関数
const createScrapedDataTableIfNotExists = async (db) => {
    return new Promise((resolve, reject) => {
        db.run(`
            CREATE TABLE IF NOT EXISTS scraped_data (
                id TEXT PRIMARY KEY,
                date TEXT,
                hole TEXT,
                machine TEXT,
                machine_number INTEGER,
                diff INTEGER,
                game INTEGER,
                big INTEGER,
                reg INTEGER,
                combined_rate TEXT,
                max_my INTEGER,
                max_mdia INTEGER,
                win INTEGER,
                timestamp TEXT
            )
        `, (err) => (err ? reject(err) : resolve()));
    });
};

// データの保存
const saveDiffData = async (db, data) => {
    const formattedData = util.formatDiffData(data);
    await createScrapedDataTableIfNotExists(db);
    return new Promise((resolve, reject) => {
        db.serialize(() => {
            const stmt = db.prepare(`
                INSERT OR IGNORE INTO scraped_data (
                    id, date, hole, machine, machine_number, diff, game, big, reg, combined_rate, max_my, max_mdia, win, timestamp
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            `);

            formattedData.forEach(row => {
                stmt.run([
                    `${row.date}_${row.hole}_${row.machine_number}`,
                    row.date,
                    row.hole,
                    row.machine,
                    row.machine_number,
                    row.diff,
                    row.game,
                    row.big,
                    row.reg,
                    row.combined_rate,
                    row.max_my,
                    row.max_mdia,
                    row.win,
                    new Date().toISOString(),
                ]);
            });

            stmt.finalize(err => (err ? reject(err) : resolve()));
        });
    });
};

const isDiffDataExists = async (db, date, hole) => {
    await createScrapedDataTableIfNotExists(db);
    return new Promise((resolve, reject) => {
        const query = `
            SELECT COUNT(*) as count
            FROM scraped_data
            WHERE date = ? AND hole = ?
        `;
        db.get(query, [date, hole], (err, row) => {
            if (err) {
                console.error(`データ存在確認中にエラーが発生しました: ${err.message}`);
                reject(err);
            } else {
                console.log(`[${date}][${hole}] データ存在確認結果: ${row.count > 0}`);
                resolve(row.count > 0);
            }
        });
    });
};

const getDiffData = async (db, date, hole) => {
    await createScrapedDataTableIfNotExists(db);
    return new Promise((resolve, reject) => {
        const query = `
            SELECT *
            FROM scraped_data
            WHERE date = ? AND hole = ?
        `;
        db.all(query, [date, hole], (err, rows) => {
            if (err) {
                console.error(`データ取得中にエラーが発生しました: ${err.message}`);
                reject(err);
            } else {
                console.log(`[${date}][${hole}] データ取得結果: ${rows.length} 件`);
                resolve(util.formatDiffData(rows));
            }
        });
    });
};

// 特定の日付とホールのデータを削除
const deleteDiffData = async (db, date, hole) => {
    await createScrapedDataTableIfNotExists(db);
    return new Promise((resolve, reject) => {
        const query = `
            DELETE FROM scraped_data
            WHERE date = ? AND hole = ?
        `;
        db.run(query, [date, hole], function(err) {
            if (err) {
                console.error(`[${date}][${hole}] データ削除中にエラーが発生しました: ${err.message}`);
                reject(err);
            } else {
                console.log(`[${date}][${hole}] データ削除結果: ${this.changes} 件削除`);
                resolve(this.changes);
            }
        });
    });
};

// 日付範囲とホール（オプション）でデータを削除
const deleteDiffDataRange = async (db, startDate, endDate, hole = null) => {
    await createScrapedDataTableIfNotExists(db);
    return new Promise((resolve, reject) => {
        let query;
        let params;
        
        if (hole) {
            query = `
                DELETE FROM scraped_data
                WHERE date >= ? AND date <= ? AND hole = ?
            `;
            params = [startDate, endDate, hole];
        } else {
            query = `
                DELETE FROM scraped_data
                WHERE date >= ? AND date <= ?
            `;
            params = [startDate, endDate];
        }
        
        db.run(query, params, function(err) {
            if (err) {
                console.error(`[${startDate}〜${endDate}][${hole || '全店舗'}] データ削除中にエラーが発生しました: ${err.message}`);
                reject(err);
            } else {
                console.log(`[${startDate}〜${endDate}][${hole || '全店舗'}] データ削除結果: ${this.changes} 件削除`);
                resolve(this.changes);
            }
        });
    });
};

/**
 * 特定の日付・店舗の機種数（ユニーク数）を取得
 * @param {object} db - SQLiteデータベース接続
 * @param {string} date - 日付
 * @param {string} hole - 店舗名
 * @returns {Promise<number>} 機種数
 */
const getMachineCount = async (db, date, hole) => {
    await createScrapedDataTableIfNotExists(db);
    return new Promise((resolve, reject) => {
        const query = `
            SELECT COUNT(DISTINCT machine) as count
            FROM scraped_data
            WHERE date = ? AND hole = ?
        `;
        db.get(query, [date, hole], (err, row) => {
            if (err) {
                console.error(`[${date}][${hole}] 機種数取得中にエラーが発生しました: ${err.message}`);
                reject(err);
            } else {
                console.log(`[${date}][${hole}] 保存済み機種数: ${row.count}`);
                resolve(row.count);
            }
        });
    });
};

/**
 * 期間内の全データを日付ごとにグループ化して取得
 * @param {object} db - SQLiteデータベース接続
 * @param {string} startDate - 開始日付 (YYYY-MM-DD)
 * @param {string} endDate - 終了日付 (YYYY-MM-DD)
 * @returns {Promise<Array<{date: string, data: Array}>>} 日付ごとのデータ配列
 */
const getDiffDataRange = async (db, startDate, endDate) => {
    await createScrapedDataTableIfNotExists(db);
    return new Promise((resolve, reject) => {
        const query = `
            SELECT *
            FROM scraped_data
            WHERE date >= ? AND date <= ?
            ORDER BY date ASC
        `;
        db.all(query, [startDate, endDate], (err, rows) => {
            if (err) {
                console.error(`[${startDate}〜${endDate}] データ取得中にエラーが発生しました: ${err.message}`);
                reject(err);
            } else {
                // 日付ごとにグループ化
                const groupedByDate = {};
                rows.forEach(row => {
                    if (!groupedByDate[row.date]) {
                        groupedByDate[row.date] = [];
                    }
                    groupedByDate[row.date].push(row);
                });
                
                // 日付順にソートして配列に変換
                const result = Object.keys(groupedByDate)
                    .sort()
                    .map(date => ({
                        date,
                        data: util.formatDiffData(groupedByDate[date])
                    }));
                
                console.log(`[${startDate}〜${endDate}] データ取得結果: ${result.length} 日分, 合計 ${rows.length} 件`);
                resolve(result);
            }
        });
    });
};

const sqlite = {
    createScrapedDataTableIfNotExists,
    saveDiffData,
    isDiffDataExists,
    getDiffData,
    deleteDiffData,
    deleteDiffDataRange,
    getMachineCount,
    getDiffDataRange,
};

export default sqlite;