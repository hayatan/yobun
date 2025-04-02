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

// SQLiteの復元処理
const restoreSQLite = async () => {
    try {
        console.log('GCSバックアップからSQLiteを復元中...');
        execSync(`litestream restore -o ${dbPath} youbun-sqlite/sqlite-backup`);
        console.log('SQLiteデータベースを復元しました。');
    } catch (err) {
        console.log('復元失敗。新しいデータベースを使用します。');
    }
};

module.exports = {
    db,
    restoreSQLite,
};