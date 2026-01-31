import 'dotenv/config';
import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';

// ============================================================================
// グローバルエラーハンドラー（プロセス終了を防ぐ）
// ============================================================================

// 未処理のPromise rejectionをキャッチ
process.on('unhandledRejection', (reason, promise) => {
    console.error('[グローバル] 未処理のPromise rejection:', reason);
    // プロセスを終了させない（ログのみ）
});

// 未処理の例外をキャッチ
process.on('uncaughtException', (error) => {
    console.error('[グローバル] 未処理の例外:', error);
    // 致命的なエラーでない限りプロセスを継続
    // 注意: 一部の致命的エラーではプロセス再起動が必要な場合あり
});

// DB初期化
import bigquery from './src/db/bigquery/init.js';
import db from './src/db/sqlite/init.js';

// ユーティリティ
import { getLockStatus, releaseLock } from './src/util/lock.js';

// ルーター
import createScrapeRouter from './src/api/routes/scrape.js';
import createSyncRouter from './src/api/routes/sync.js';
import createForceRescrapeRouter from './src/api/routes/force-rescrape.js';
import createDataStatusRouter from './src/api/routes/data-status.js';
import createDatamartRouter from './src/api/routes/datamart.js';
import createScheduleRouter from './src/api/routes/schedule.js';
import createFailuresRouter from './src/api/routes/failures.js';
import createCorrectionsRouter from './src/api/routes/corrections.js';
import createDedupeRouter from './src/api/routes/dedupe.js';
import createEventsRouter from './src/api/routes/events.js';
import createEventTypesRouter from './src/api/routes/event-types.js';

// スケジューラー
import { initScheduler } from './src/scheduler/index.js';

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

// ロック状態確認エンドポイント
app.get('/api/lock', async (req, res) => {
    const lockStatus = await getLockStatus();
    res.json({
        locked: lockStatus !== null && !lockStatus.isExpired,
        status: lockStatus,
    });
});

// ロック強制解除エンドポイント
app.delete('/api/lock', async (req, res) => {
    try {
        await releaseLock();
        res.json({ success: true, message: 'ロックを解除しました' });
    } catch (error) {
        console.error('ロック解除中にエラーが発生しました:', error);
        res.status(500).json({ success: false, message: error.message });
    }
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

// 重複削除関連（HTMLページと API）
app.get('/util/dedupe', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'util', 'dedupe.html'));
});
const dedupeRouter = createDedupeRouter(bigquery, db);
app.use('/util/dedupe', dedupeRouter);

// 再取得API（ダッシュボードから使用）
const forceRescrapeRouter = createForceRescrapeRouter(bigquery, db);
app.use('/util/force-rescrape', forceRescrapeRouter);

// データ取得状況API
const dataStatusRouter = createDataStatusRouter(bigquery, db);
app.use('/api/data-status', dataStatusRouter);

// ダッシュボードページ（トップページとしても使用）
app.get('/dashboard', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'dashboard.html'));
});

// トップページ → ダッシュボード
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'dashboard.html'));
});

// データマート関連（HTMLページと API）
app.get('/datamart', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'datamart.html'));
});
const datamartRouter = createDatamartRouter(bigquery, db);
app.use('/api/datamart', datamartRouter);

// スケジュール管理（HTMLページと API）
app.get('/schedule', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'schedule.html'));
});
const scheduleRouter = createScheduleRouter(bigquery, db);
app.use('/api/schedules', scheduleRouter);

// 失敗管理・手動補正（HTMLページと API）
app.get('/failures', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'failures.html'));
});
const failuresRouter = createFailuresRouter(db);
app.use('/api/failures', failuresRouter);
const correctionsRouter = createCorrectionsRouter(bigquery, db);
app.use('/api/corrections', correctionsRouter);

// イベント管理（HTMLページと API）
app.get('/events', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'events.html'));
});
const eventsRouter = createEventsRouter(bigquery, db);
app.use('/api/events', eventsRouter);
const eventTypesRouter = createEventTypesRouter(db);
app.use('/api/event-types', eventTypesRouter);

// ============================================================================
// サーバー起動
// ============================================================================

const PORT = process.env.PORT || 8080;
app.listen(PORT, async () => {
    console.log(`サーバーがポート ${PORT} で起動しました。`);
    if (process.env.NODE_ENV === 'development') {
        console.log('開発環境で起動中...');
    }
    
    // スケジューラーを初期化（ローカル実行時のみ）
    if (process.env.ENABLE_SCHEDULER !== 'false') {
        try {
            await initScheduler(bigquery, db);
        } catch (error) {
            console.error('スケジューラーの初期化に失敗しました:', error);
        }
    }
});
