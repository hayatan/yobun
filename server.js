import 'dotenv/config';
import express from 'express';
import bigquery from './src/db/bigquery/init.js';
import db from './src/db/sqlite/init.js';
import { runScrape } from './src/app.js';
import path from 'path';
import { fileURLToPath } from 'url';
import { getTable, saveToBigQuery, deleteBigQueryData } from './src/db/bigquery/operations.js';
import sqlite from './src/db/sqlite/operations.js';
import scrapeSlotDataByMachine from './src/services/slorepo/scraper.js';
import config from './src/config/slorepo-config.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();

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

// スクレイピングの状態管理
let scrapingState = {
    isRunning: false,
    startTime: null,
    progress: {
        current: 0,
        total: 0,
        message: ''
    },
    lastError: null
};

// 同期処理の状態管理
let syncState = {
    isRunning: false,
    startTime: null,
    progress: {
        current: 0,
        total: 0,
        message: ''
    },
    lastError: null
};

// 強制再取得の状態管理
let forceRescrapeState = {
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
const updateScrapingState = (updates) => {
    scrapingState = { ...scrapingState, ...updates };
};

// スクレイピングの進捗を更新する関数
const updateProgress = (current, total, message) => {
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
        const { startDate, endDate } = req.body;
        
        if (!startDate || !endDate) {
            return res.status(400).json({
                error: '開始日と終了日を指定してください',
                status: scrapingState
            });
        }

        updateScrapingState({
            isRunning: true,
            startTime: new Date(),
            lastError: null
        });

        // 非同期でスクレイピングを実行
        runScrape(bigquery, db, updateProgress, { startDate, endDate })
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

// 同期処理のフロントエンド
app.get('/util/sync', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'util', 'sync.html'));
});

// 強制再取得のフロントエンド
app.get('/util/force-rescrape', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'util', 'force-rescrape.html'));
});

// 同期処理のエンドポイント
app.post('/util/sync', express.json(), async (req, res) => {
    if (syncState.isRunning) {
        return res.status(409).json({ 
            error: '同期処理は既に実行中です',
            status: syncState
        });
    }

    try {
        const { date } = req.body;
        
        if (!date) {
            return res.status(400).json({
                error: '日付を指定してください',
                status: syncState
            });
        }

        syncState = {
            isRunning: true,
            startTime: new Date(),
            progress: {
                current: 0,
                total: 0,
                message: '同期処理を開始します...'
            },
            lastError: null
        };

        // SQLiteのデータを確認
        console.log('検索する日付:', date);
        const data = await sqlite.getDiffDataDate(db, date);
        console.log('検索結果:', data);

        if (data.length === 0) {
            syncState = {
                isRunning: false,
                startTime: null,
                progress: {
                    current: 0,
                    total: 0,
                    message: '指定された日付のデータが存在しません'
                },
                lastError: null
            };
            return res.status(404).json({ 
                message: '指定された日付のデータが存在しません',
                status: syncState
            });
        }

        // BigQueryのテーブルを取得（存在しない場合は作成）
        const datasetId = 'slot_data';
        const dateTable = `data_${date.replace(/-/g, '')}`;
        const table = await getTable(bigquery, datasetId, dateTable);

        if (data.length > 0) {
            // BigQueryにデータを保存
            await saveToBigQuery(table, data);
        }

        syncState = {
            isRunning: false,
            startTime: null,
            progress: {
                current: data.length,
                total: data.length,
                message: '同期処理が完了しました'
            },
            lastError: null
        };

        res.status(200).json({ 
            message: '同期処理が完了しました',
            status: syncState
        });
    } catch (error) {
        syncState = {
            isRunning: false,
            startTime: null,
            progress: {
                current: 0,
                total: 0,
                message: '同期処理中にエラーが発生しました'
            },
            lastError: error.message
        };
        res.status(500).json({ 
            error: '同期処理中にエラーが発生しました',
            status: syncState
        });
    }
});

// 同期処理の状態を取得するエンドポイント
app.get('/util/sync/status', (req, res) => {
    res.json(syncState);
});

// 強制再取得のエンドポイント
app.post('/util/force-rescrape', express.json(), async (req, res) => {
    if (forceRescrapeState.isRunning) {
        return res.status(409).json({ 
            error: '強制再取得は既に実行中です',
            status: forceRescrapeState
        });
    }

    try {
        const { date, holeName } = req.body;
        
        if (!date || !holeName) {
            return res.status(400).json({
                error: '日付とホール名を指定してください',
                status: forceRescrapeState
            });
        }

        // ホール設定を確認
        const hole = config.holes.find(h => h.name === holeName);
        if (!hole) {
            return res.status(400).json({
                error: '指定されたホールが見つかりません',
                status: forceRescrapeState
            });
        }

        forceRescrapeState = {
            isRunning: true,
            startTime: new Date(),
            progress: {
                current: 0,
                total: 4,
                message: '強制再取得を開始します...'
            },
            lastError: null
        };

        // 非同期で強制再取得を実行
        (async () => {
            try {
                // Step 1: SQLiteからデータを削除
                forceRescrapeState.progress = {
                    current: 1,
                    total: 4,
                    message: `[${date}][${holeName}] SQLiteからデータを削除中...`
                };
                await sqlite.deleteDiffData(db, date, holeName);

                // Step 2: BigQueryからデータを削除
                forceRescrapeState.progress = {
                    current: 2,
                    total: 4,
                    message: `[${date}][${holeName}] BigQueryからデータを削除中...`
                };
                const datasetId = 'slot_data';
                const tableId = `data_${date.replace(/-/g, '')}`;
                const table = await getTable(bigquery, datasetId, tableId);
                await deleteBigQueryData(table, holeName);

                // Step 3: 新しいデータをスクレイピング
                forceRescrapeState.progress = {
                    current: 3,
                    total: 4,
                    message: `[${date}][${holeName}] 新しいデータをスクレイピング中...`
                };
                const newData = await scrapeSlotDataByMachine(date, hole.code);
                
                // SQLiteに保存
                await sqlite.saveDiffData(db, newData);

                // Step 4: BigQueryに保存
                forceRescrapeState.progress = {
                    current: 4,
                    total: 4,
                    message: `[${date}][${holeName}] BigQueryにデータを保存中...`
                };
                await saveToBigQuery(table, newData);

                forceRescrapeState = {
                    isRunning: false,
                    startTime: null,
                    progress: {
                        current: 4,
                        total: 4,
                        message: `[${date}][${holeName}] 強制再取得が完了しました`
                    },
                    lastError: null
                };
            } catch (error) {
                console.error('強制再取得中にエラーが発生しました:', error);
                forceRescrapeState = {
                    isRunning: false,
                    startTime: null,
                    progress: {
                        current: 0,
                        total: 4,
                        message: '強制再取得中にエラーが発生しました'
                    },
                    lastError: error.message
                };
            }
        })();

        res.status(202).json({ 
            message: '強制再取得を開始しました',
            status: forceRescrapeState
        });
    } catch (error) {
        forceRescrapeState = {
            isRunning: false,
            startTime: null,
            progress: {
                current: 0,
                total: 4,
                message: '強制再取得の開始に失敗しました'
            },
            lastError: error.message
        };
        res.status(500).json({ 
            error: '強制再取得の開始に失敗しました',
            status: forceRescrapeState
        });
    }
});

// 強制再取得の状態を取得するエンドポイント
app.get('/util/force-rescrape/status', (req, res) => {
    res.json(forceRescrapeState);
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
