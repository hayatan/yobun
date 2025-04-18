import 'dotenv/config';
import express from 'express';
import bigquery from './src/db/bigquery/init.js';
import db from './src/db/sqlite/init.js';
import { runScrape } from './src/app.js';

const app = express();

// ヘルスチェックエンドポイント
app.get('/health', (req, res) => {
    res.status(200).send('OK');
});

// スクレイピング実行エンドポイント
app.get('/run-scrape', async (req, res) => {
    try {
        await runScrape(bigquery, db);
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

// Promise 化するわよっ！
const execAsync = (sql) => new Promise((resolve, reject) => {
    db.exec(sql, (err) => {
        if (err) reject(err);
        else resolve();
    });
});

const allAsync = (sql) => new Promise((resolve, reject) => {
    db.all(sql, (err, rows) => {
        if (err) reject(err);
        else resolve(rows);
    });
});

app.get('/test-write', async (req, res) => {
    try {
        await execAsync(`
            CREATE TABLE IF NOT EXISTS test (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            message TEXT
            );
        `);

        await execAsync(`
            INSERT INTO test (message) VALUES ('妹が作ったデータです♥');
        `);

        const rows = await allAsync("SELECT * FROM test");
        res.json(rows);
    } catch (err) {
        console.error("やらかしたわね…", err);
        res.status(500).send("ちょっと失敗したかも…💦");
    }
});

app.get('/test-read', async (req, res) => {
    try {
        const rows = await allAsync("SELECT * FROM test");
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
    if (process.env.NODE_ENV === 'development') {
        console.log('開発環境で起動中...');
    }
});
