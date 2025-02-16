require('dotenv').config();
const express = require('express');
const { restoreSQLite } = require('./src/app');

const app = express();

// ヘルスチェックエンドポイント
app.get('/health', (req, res) => {
    res.status(200).send('OK');
});

// スクレイピング実行エンドポイント
app.get('/run-scrape', async (req, res) => {
    try {
        const { runScrape } = require('./src/app');
        await runScrape();
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

// サーバー起動
const PORT = process.env.PORT || 8080;
app.listen(PORT, async () => {
    console.log(`サーバーがポート ${PORT} で起動しました。`);
    await restoreSQLite(); // 起動時にSQLiteを復元
});
