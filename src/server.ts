import 'dotenv/config';
import express from 'express';
import bigquery from './db/bigquery/init.js';
import db from './db/sqlite/init.js';
import { runScrape } from './app.ts';
import path from 'path';
import { fileURLToPath } from 'url';
import util from './util/common.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

// 静的ファイルを提供
app.use(express.static(path.join(__dirname, 'public')));

// スクレイピングの状態管理
interface ScrapingState {
    isRunning: boolean;
    startTime: Date | null;
    progress: {
        current: number;
        total: number;
        message: string;
    };
    lastError: string | null;
}

let scrapingState: ScrapingState = {
    isRunning: false,
    startTime: null,
    progress: {
        current: 0,
        total: 0,
        message: ''
    },
    lastError: null
};

// スクレイピングの状態を更新する関数
const updateScrapingState = (updates: Partial<ScrapingState>): void => {
    scrapingState = { ...scrapingState, ...updates };
};

// スクレイピングの進捗を更新する関数
const updateProgress = (current: number, total: number, message: string): void => {
    scrapingState.progress = { current, total, message };
};

// ヘルスチェックエンドポイント
app.get('/health', (req, res) => {
    res.status(200).send('OK');
});

// スクレイピングの状態を取得するエンドポイント
app.get('/status', (req, res) => {
    res.json(scrapingState);
});

// Pub/Subメッセージを処理するエンドポイント
app.post('/pubsub', express.json(), async (req, res) => {
    if (scrapingState.isRunning) {
        return res.status(409).json({ 
            error: 'スクレイピングは既に実行中です',
            status: scrapingState
        });
    }

    try {
        updateScrapingState({
            isRunning: true,
            startTime: new Date(),
            lastError: null
        });

        // 非同期でスクレイピングを実行
        const { startDate, endDate } = util.getDefaultDateRange();
        runScrape(bigquery, db, startDate, endDate, updateProgress)
            .then(() => {
                updateScrapingState({
                    isRunning: false,
                    progress: { current: 0, total: 0, message: '完了' }
                });
            })
            .catch(error => {
                updateScrapingState({
                    isRunning: false,
                    lastError: error.message
                });
            });

        res.status(202).json({ 
            message: 'スクレイピングを開始しました',
            status: scrapingState
        });
    } catch (error) {
        updateScrapingState({
            isRunning: false,
            lastError: error.message
        });
        res.status(500).json({ 
            error: 'スクレイピングの開始に失敗しました',
            status: scrapingState
        });
    }
});

// スクレイピング実行エンドポイント
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Promise 化するわよっ！
const execAsync = (sql: string): Promise<void> => new Promise((resolve, reject) => {
    db.exec(sql, (err) => {
        if (err) reject(err);
        else resolve();
    });
});

const allAsync = (sql: string): Promise<any[]> => new Promise((resolve, reject) => {
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