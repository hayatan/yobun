/**
 * 共通ステータスヘッダーコンポーネント
 * 
 * 全ページで使用される共通ヘッダーを生成し、
 * ジョブの実行状態をリアルタイムで表示する
 */

class StatusHeader {
    constructor() {
        this.pollInterval = 30000; // 30秒
        this.pollTimer = null;
        this.currentStatus = {
            scraping: null,
            lock: null,
        };
    }

    /**
     * ヘッダーを初期化
     */
    init() {
        this.render();
        this.startPolling();
        this.fetchStatus();
    }

    /**
     * ヘッダーHTMLをレンダリング
     */
    render() {
        const header = document.createElement('div');
        header.id = 'yobun-header';
        header.innerHTML = `
            <nav class="header-nav">
                <a href="/" class="header-brand">Yobun</a>
                <div class="header-links">
                    <a href="/" class="nav-link">ダッシュボード</a>
                    <a href="/schedule" class="nav-link">スケジュール</a>
                    <a href="/datamart" class="nav-link">データマート</a>
                    <a href="/failures" class="nav-link">失敗管理</a>
                    <a href="/events" class="nav-link">イベント</a>
                    <a href="/util/sync" class="nav-link">同期</a>
                    <a href="/util/dedupe" class="nav-link">重複削除</a>
                </div>
                <div id="status-indicator" class="status-indicator">
                    <span class="status-dot"></span>
                    <span class="status-text">確認中...</span>
                </div>
            </nav>
        `;

        // スタイルを追加
        const style = document.createElement('style');
        style.textContent = `
            #yobun-header {
                background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                color: #fff;
                padding: 0;
                position: sticky;
                top: 0;
                z-index: 1000;
                box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3);
            }
            
            .header-nav {
                max-width: 1400px;
                margin: 0 auto;
                display: flex;
                align-items: center;
                padding: 0 20px;
                height: 56px;
            }
            
            .header-brand {
                font-size: 1.4rem;
                font-weight: bold;
                color: #e94560;
                text-decoration: none;
                margin-right: 40px;
            }
            
            .header-brand:hover {
                color: #ff6b6b;
            }
            
            .header-links {
                display: flex;
                gap: 8px;
                flex: 1;
            }
            
            .nav-link {
                color: #a0a0a0;
                text-decoration: none;
                padding: 8px 16px;
                border-radius: 4px;
                transition: all 0.2s;
                font-size: 0.9rem;
            }
            
            .nav-link:hover {
                color: #fff;
                background: rgba(255, 255, 255, 0.1);
            }
            
            .nav-link.active {
                color: #fff;
                background: rgba(233, 69, 96, 0.3);
            }
            
            .status-indicator {
                display: flex;
                align-items: center;
                gap: 8px;
                padding: 8px 16px;
                border-radius: 20px;
                background: rgba(255, 255, 255, 0.05);
                cursor: pointer;
                transition: all 0.2s;
            }
            
            .status-indicator:hover {
                background: rgba(255, 255, 255, 0.1);
            }
            
            .status-dot {
                width: 10px;
                height: 10px;
                border-radius: 50%;
                background: #888;
                animation: none;
            }
            
            .status-dot.idle {
                background: #4ade80;
            }
            
            .status-dot.running {
                background: #fbbf24;
                animation: pulse 1.5s infinite;
            }
            
            .status-dot.locked {
                background: #f87171;
                animation: pulse 1.5s infinite;
            }
            
            .status-dot.error {
                background: #ef4444;
            }
            
            .status-text {
                font-size: 0.85rem;
                color: #a0a0a0;
            }
            
            @keyframes pulse {
                0%, 100% { opacity: 1; }
                50% { opacity: 0.5; }
            }
            
            /* 他の要素への影響を調整 */
            body {
                padding-top: 0 !important;
            }
            
            /* ヘッダーの下に余白を追加 */
            #yobun-header + * {
                margin-top: 0;
            }
        `;

        document.head.appendChild(style);
        document.body.insertBefore(header, document.body.firstChild);

        // クリックイベント
        document.getElementById('status-indicator').addEventListener('click', () => {
            window.location.href = '/dashboard';
        });

        // 現在のページのリンクをアクティブにする
        this.setActiveLink();
    }

    /**
     * 現在のページのリンクをアクティブにする
     */
    setActiveLink() {
        const path = window.location.pathname;
        const links = document.querySelectorAll('.nav-link');
        links.forEach(link => {
            const href = link.getAttribute('href');
            // / は / と /dashboard の両方でアクティブ
            if (href === '/' && (path === '/' || path === '/dashboard')) {
                link.classList.add('active');
            } else if (href !== '/' && path.startsWith(href)) {
                link.classList.add('active');
            }
        });
    }

    /**
     * ポーリング開始
     */
    startPolling() {
        this.pollTimer = setInterval(() => this.fetchStatus(), this.pollInterval);
    }

    /**
     * ポーリング停止
     */
    stopPolling() {
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = null;
        }
    }

    /**
     * ステータスを取得
     */
    async fetchStatus() {
        try {
            const [statusRes, lockRes] = await Promise.all([
                fetch('/status'),
                fetch('/api/lock'),
            ]);

            const scrapingStatus = await statusRes.json();
            const lockStatus = await lockRes.json();

            this.currentStatus.scraping = scrapingStatus;
            this.currentStatus.lock = lockStatus;

            this.updateIndicator();
        } catch (error) {
            console.error('ステータス取得エラー:', error);
            this.showError();
        }
    }

    /**
     * インジケーターを更新
     */
    updateIndicator() {
        const dot = document.querySelector('.status-dot');
        const text = document.querySelector('.status-text');

        if (!dot || !text) return;

        const scraping = this.currentStatus.scraping;
        const lock = this.currentStatus.lock;

        // ステータスの優先順位: 実行中 > ロック中 > アイドル
        if (scraping?.isRunning) {
            dot.className = 'status-dot running';
            const progress = scraping.progress;
            if (progress && progress.total > 0) {
                text.textContent = `スクレイピング中: ${progress.current}/${progress.total}`;
            } else {
                text.textContent = `スクレイピング中: ${progress?.message || '処理中...'}`;
            }
        } else if (lock?.locked) {
            dot.className = 'status-dot locked';
            const status = lock.status;
            const env = status?.environment || '不明';
            const hours = status?.ageHours || 0;
            const mins = status?.ageMinutes || 0;
            text.textContent = `ロック中 (${env}, ${hours}時間${mins}分)`;
        } else {
            dot.className = 'status-dot idle';
            text.textContent = 'アイドル';
        }
    }

    /**
     * エラー表示
     */
    showError() {
        const dot = document.querySelector('.status-dot');
        const text = document.querySelector('.status-text');

        if (dot) dot.className = 'status-dot error';
        if (text) text.textContent = '接続エラー';
    }
}

// グローバルインスタンス
const statusHeader = new StatusHeader();

// DOMContentLoadedで初期化
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => statusHeader.init());
} else {
    statusHeader.init();
}

// エクスポート（モジュールとして使用する場合）
if (typeof module !== 'undefined' && module.exports) {
    module.exports = StatusHeader;
}
