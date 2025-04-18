import sqlite3 from 'sqlite3';
import 'dotenv/config';

const dbPath = process.env.SQLITE_DB_PATH;

// SQLiteデータベースの設定
const db = new sqlite3.Database(dbPath, (err) => {
    if (err) {
        console.error('SQLiteデータベース接続エラー:', err);
    } else {
        console.log('SQLiteデータベースに接続しました:', dbPath);
    }
});

export default db;