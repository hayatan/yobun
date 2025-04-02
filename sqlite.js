const sqlite3 = require('sqlite3').verbose();
const { execSync } = require('child_process');
require('dotenv').config();
const dbPath = process.env.SQLITE_DB_PATH;

// SQLiteデータベースの設定
const db = new sqlite3.Database(dbPath, (err) => {
    if (err) {
        console.error('SQLiteデータベース接続エラー:', err);
    } else {
        console.log('SQLiteデータベースに接続しました:', dbPath);
    }
});

module.exports = {
    db
};