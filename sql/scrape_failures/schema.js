// ============================================================================
// スクレイピング失敗記録スキーマ定義
// ============================================================================
// 
// スクレイピング失敗時の記録を管理するテーブルのスキーマ
// 手動補正の対象を特定するために使用
// 
// 使用方法:
//   import { SCRAPE_FAILURES_SCHEMA } from '../../sql/scrape_failures/schema.js';
//   const sqliteCreate = SCRAPE_FAILURES_SCHEMA.toSQLiteCreateTable();
// ============================================================================

import crypto from 'crypto';

export const SCRAPE_FAILURES_SCHEMA = {
    // スキーマバージョン（変更時にインクリメント）
    version: '1.0.0',
    
    // テーブル名
    tableName: 'scrape_failures',
    
    // カラム定義
    columns: [
        { 
            name: 'id', 
            sqliteType: 'TEXT PRIMARY KEY', 
            description: 'ユニークID (UUID)',
            nullable: false,
        },
        { 
            name: 'date', 
            sqliteType: 'TEXT NOT NULL', 
            description: '対象日付 (YYYY-MM-DD)',
            nullable: false,
        },
        { 
            name: 'hole', 
            sqliteType: 'TEXT NOT NULL', 
            description: '店舗名',
            nullable: false,
        },
        { 
            name: 'hole_code', 
            sqliteType: 'TEXT NOT NULL', 
            description: '店舗コード',
            nullable: false,
        },
        { 
            name: 'machine', 
            sqliteType: 'TEXT', 
            description: '機種名（特定できた場合）',
            nullable: true,
        },
        { 
            name: 'machine_url', 
            sqliteType: 'TEXT', 
            description: '機種ページURL（手動確認用）',
            nullable: true,
        },
        { 
            name: 'error_type', 
            sqliteType: 'TEXT NOT NULL', 
            description: 'エラー種別 (cloudflare/timeout/parse/network/unknown)',
            nullable: false,
        },
        { 
            name: 'error_message', 
            sqliteType: 'TEXT', 
            description: 'エラー詳細メッセージ',
            nullable: true,
        },
        { 
            name: 'failed_at', 
            sqliteType: 'TEXT NOT NULL', 
            description: '失敗日時 (ISO8601)',
            nullable: false,
        },
        { 
            name: 'status', 
            sqliteType: 'TEXT NOT NULL DEFAULT \'pending\'', 
            description: 'ステータス (pending/resolved/ignored)',
            nullable: false,
            default: 'pending',
        },
        { 
            name: 'resolved_at', 
            sqliteType: 'TEXT', 
            description: '解決日時 (ISO8601)',
            nullable: true,
        },
        { 
            name: 'resolved_method', 
            sqliteType: 'TEXT', 
            description: '解決方法 (manual/rescrape)',
            nullable: true,
        },
    ],
    
    // インデックス定義
    indexes: [
        { name: 'idx_failures_date', columns: ['date'] },
        { name: 'idx_failures_hole', columns: ['hole'] },
        { name: 'idx_failures_status', columns: ['status'] },
        { name: 'idx_failures_date_hole', columns: ['date', 'hole'] },
    ],
    
    /**
     * SQLite CREATE TABLE文を生成
     * @param {string} tableName - テーブル名（オプション）
     * @returns {string} CREATE TABLE文
     */
    toSQLiteCreateTable(tableName = 'scrape_failures') {
        const cols = this.columns.map(col => `    ${col.name} ${col.sqliteType}`).join(',\n');
        return `CREATE TABLE IF NOT EXISTS ${tableName} (\n${cols}\n)`;
    },
    
    /**
     * インデックス作成文を生成
     * @param {string} tableName - テーブル名（オプション）
     * @returns {string[]} CREATE INDEX文の配列
     */
    toSQLiteIndexes(tableName = 'scrape_failures') {
        return this.indexes.map(idx => 
            `CREATE INDEX IF NOT EXISTS ${idx.name} ON ${tableName} (${idx.columns.join(', ')})`
        );
    },
    
    /**
     * ID生成（UUID v4）
     * @returns {string} UUID
     */
    generateId() {
        return crypto.randomUUID();
    },
    
    /**
     * カラム名の一覧を取得
     * @returns {Array<string>} カラム名配列
     */
    getColumnNames() {
        return this.columns.map(col => col.name);
    },
    
    /**
     * エラー種別の定数
     */
    errorTypes: {
        CLOUDFLARE: 'cloudflare',
        TIMEOUT: 'timeout',
        PARSE: 'parse',
        NETWORK: 'network',
        UNKNOWN: 'unknown',
    },
    
    /**
     * ステータスの定数
     */
    statuses: {
        PENDING: 'pending',
        RESOLVED: 'resolved',
        IGNORED: 'ignored',
    },
    
    /**
     * 解決方法の定数
     */
    resolvedMethods: {
        MANUAL: 'manual',
        RESCRAPE: 'rescrape',
    },
};

export default SCRAPE_FAILURES_SCHEMA;
