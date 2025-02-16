require('dotenv').config();
const express = require('express');

const app = express();

// スクレイピング実行エンドポイント
app.get('/', async (req, res) => {
    try {
        res.status(200).send('yobun running...');
    } catch (error) {
        res.status(500).send(error.message);
    }
});

// サーバー起動
const PORT = 8080;
app.listen(PORT, async () => {
    console.log(`サーバーがポート ${PORT} で起動しました。`);
});
