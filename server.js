import 'dotenv/config';
import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';

// DB初期化
import bigquery from './src/db/bigquery/init.js';
import db from './src/db/sqlite/init.js';

// ルーター
import createScrapeRouter from './src/api/routes/scrape.js';
import createSyncRouter from './src/api/routes/sync.js';
import createForceRescrapeRouter from './src/api/routes/force-rescrape.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

// JSON パーサー
app.use(express.json());

// アクセスログを出力するミドルウェア
app.use((req, res, next) => {
    const timestamp = new Date().toISOString();
    const method = req.method;
    const path = req.path;
    const ip = req.ip;
    console.log(`[${timestamp}] ${method} ${path} from ${ip}`);
    next();
});

// 静的ファイルを提供
app.use(express.static(path.join(__dirname, 'public')));

// ============================================================================
// ルーティング
// ============================================================================

// ヘルスチェックエンドポイント
app.get('/health', (req, res) => {
    res.status(200).send('OK');
});

// スクレイピング関連
const scrapeRouter = createScrapeRouter(bigquery, db);
app.use('/', scrapeRouter);

// 同期関連（HTMLページと API）
app.get('/util/sync', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'util', 'sync.html'));
});
const syncRouter = createSyncRouter(bigquery, db);
app.use('/util/sync', syncRouter);

// 強制再取得関連（HTMLページと API）
app.get('/util/force-rescrape', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'util', 'force-rescrape.html'));
});
const forceRescrapeRouter = createForceRescrapeRouter(bigquery, db);
app.use('/util/force-rescrape', forceRescrapeRouter);

// トップページ
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// ============================================================================
// テスト用エンドポイント（開発時のみ）
// ============================================================================

// Promise 化ヘルパー
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

// ============================================================================
// サーバー起動
// ============================================================================

const PORT = process.env.PORT || 8080;
app.listen(PORT, async () => {
    console.log(`サーバーがポート ${PORT} で起動しました。`);
    if (process.env.NODE_ENV === 'development') {
        console.log('開発環境で起動中...');
    }
});
