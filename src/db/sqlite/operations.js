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
                console.log(`[${date}] データ取得結果: ${rows.length} 件`);
                resolve(util.formatDiffData(rows));
            }
        });
    });
};

const getDiffDataDate = async (db, date) => {
    await createScrapedDataTableIfNotExists(db);
    return new Promise((resolve, reject) => {
        const query = `
            SELECT *
            FROM scraped_data
            WHERE date = ?
        `;
        db.all(query, [date], (err, rows) => {
            if (err) {
                console.error(`データ取得中にエラーが発生しました: ${err.message}`);
                reject(err);
            } else {
                console.log(`[${date}] データ取得結果: ${rows.length} 件`);
                resolve(util.formatDiffData(rows));
            }
        });
    });
};

const sqlite = {
    createScrapedDataTableIfNotExists,
    saveDiffData,
    isDiffDataExists,
    getDiffData,
    getDiffDataDate,
};

export default sqlite;