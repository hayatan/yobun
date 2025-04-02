require('dotenv').config();
const express = require('express');
const { bigQuery } = require('./bigquery');
const { db, restoreSQLite } = require('./sqlite');
const { runScrape } = require('./src/app');

const app = express();

// ヘルスチェックエンドポイント
app.get('/health', (req, res) => {
    res.status(200).send('OK');
});

// スクレイピング実行エンドポイント
app.get('/run-scrape', async (req, res) => {
    try {
        await runScrape(bigQuery, db);
        res.status(200).send('スクレイピング処理が完了しました。');
    } catch (error) {
        console.error('スクレイピング処理中にエラーが発生しました:', error);
        res.status(500).send('スクレイピング処理中にエラーが発生しました。');
    }
});

// スクレイピング実行エンドポイント
app.get('/', async (req, res) => {
    try {
        res.status(200).send('yobun running...');
    } catch (error) {
        res.status(500).send(error.message);
    }
});

app.get('/test-write', async (req, res) => {
    try {
        db.exec(`
        CREATE TABLE IF NOT EXISTS test (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          message TEXT
        );
        `);

        db.exec(`
        INSERT INTO test (message) VALUES ('妹が作ったデータです♥');
        `);

        const rows = db.all("SELECT * FROM test");
        res.json(rows);
    } catch (err) {
        console.error("やらかしたわね…", err);
        res.status(500).send("ちょっと失敗したかも…💦");
    }
});

app.get('/test-read', async (req, res) => {
    try {
        const rows = db.all("SELECT * FROM test");
        res.json(rows);
    } catch (err) {
        console.error("読めなかったんだけど！？💢", err);
        res.status(500).send("読み込み失敗…妹のせいじゃないんだからねっ！");
    }
});

// サーバー起動
const PORT = 8080;
app.listen(PORT, async () => {
    console.log(`サーバーがポート ${PORT} で起動しました。`);
    await restoreSQLite(); // 起動時にSQLiteを復元
});
