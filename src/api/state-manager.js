// ============================================================================
// ジョブ状態管理
// ============================================================================
// 
// スクレイピング、同期、強制再取得などのジョブの状態を一元管理
// ============================================================================

/**
 * ジョブの状態オブジェクト
 * @typedef {Object} JobState
 * @property {boolean} isRunning - 実行中かどうか
 * @property {Date|null} startTime - 開始時刻
 * @property {Object} progress - 進捗情報
 * @property {number} progress.current - 現在の進捗
 * @property {number} progress.total - 総数
 * @property {string} progress.message - メッセージ
 * @property {string|null} lastError - 最後のエラーメッセージ
 */

/**
 * 初期状態を生成
 * @returns {JobState}
 */
const createInitialState = () => ({
    isRunning: false,
    startTime: null,
    progress: {
        current: 0,
        total: 0,
        message: ''
    },
    lastError: null
});

/**
 * ジョブ状態マネージャークラス
 */
class JobStateManager {
    constructor() {
        this.states = {
            scraping: createInitialState(),
            sync: createInitialState(),
            forceRescrape: createInitialState(),
        };
    }

    /**
     * 状態を取得
     * @param {string} jobType - ジョブタイプ (scraping, sync, forceRescrape)
     * @returns {JobState}
     */
    getState(jobType) {
        return this.states[jobType];
    }

    /**
     * 状態を更新
     * @param {string} jobType - ジョブタイプ
     * @param {Partial<JobState>} updates - 更新内容
     */
    updateState(jobType, updates) {
        this.states[jobType] = { ...this.states[jobType], ...updates };
    }

    /**
     * 進捗を更新
     * @param {string} jobType - ジョブタイプ
     * @param {number} current - 現在の進捗
     * @param {number} total - 総数
     * @param {string} message - メッセージ
     */
    updateProgress(jobType, current, total, message) {
        this.states[jobType].progress = { current, total, message };
    }

    /**
     * ジョブ開始
     * @param {string} jobType - ジョブタイプ
     */
    startJob(jobType) {
        this.states[jobType] = {
            isRunning: true,
            startTime: new Date(),
            progress: { current: 0, total: 0, message: '開始...' },
            lastError: null,
        };
    }

    /**
     * ジョブ完了
     * @param {string} jobType - ジョブタイプ
     * @param {string} message - 完了メッセージ
     */
    completeJob(jobType, message = '完了') {
        this.states[jobType].isRunning = false;
        this.states[jobType].progress.message = message;
    }

    /**
     * ジョブエラー
     * @param {string} jobType - ジョブタイプ
     * @param {string} errorMessage - エラーメッセージ
     */
    failJob(jobType, errorMessage) {
        this.states[jobType].isRunning = false;
        this.states[jobType].lastError = errorMessage;
    }

    /**
     * 実行中かどうか
     * @param {string} jobType - ジョブタイプ
     * @returns {boolean}
     */
    isRunning(jobType) {
        return this.states[jobType].isRunning;
    }
}

// シングルトンインスタンス
const stateManager = new JobStateManager();

export default stateManager;
export { JobStateManager, createInitialState };
