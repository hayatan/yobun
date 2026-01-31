// ============================================================================
// イベントスキーマ定義（SQLite/BigQuery共用）
// ============================================================================
// 
// 店舗のイベント情報（LINE告知、特定日など）を管理するテーブルのスキーマ
// 分析時にJOINして使用するため、SQLiteとBigQuery両方に同期
// 
// 使用方法:
//   import { EVENTS_SCHEMA } from '../../sql/events/schema.js';
//   const bqSchema = EVENTS_SCHEMA.toBigQuerySchema();
//   const sqliteCreate = EVENTS_SCHEMA.toSQLiteCreateTable();
// ============================================================================

import crypto from 'crypto';

export const EVENTS_SCHEMA = {
    // スキーマバージョン（変更時にインクリメント）
    version: '1.0.0',
    
    // テーブル名
    tableName: 'events',
    
    // カラム定義
    columns: [
        { 
            name: 'id', 
            bqType: 'STRING', 
            sqliteType: 'TEXT PRIMARY KEY', 
            description: 'ユニークID (UUID)',
            nullable: false,
        },
        { 
            name: 'date', 
            bqType: 'STRING', 
            sqliteType: 'TEXT NOT NULL', 
            description: '日付 (YYYY-MM-DD)',
            nullable: false,
        },
        { 
            name: 'hole', 
            bqType: 'STRING', 
            sqliteType: 'TEXT NOT NULL', 
            description: '店舗名',
            nullable: false,
        },
        { 
            name: 'event', 
            bqType: 'STRING', 
            sqliteType: 'TEXT NOT NULL', 
            description: 'イベント種類 (LINE告知、特定日など)',
            nullable: false,
        },
        { 
            name: 'description', 
            bqType: 'STRING', 
            sqliteType: 'TEXT', 
            description: '説明（任意）',
            nullable: true,
        },
        { 
            name: 'created_at', 
            bqType: 'TIMESTAMP', 
            sqliteType: 'TEXT NOT NULL', 
            description: '作成日時 (ISO8601)',
            nullable: false,
        },
        { 
            name: 'updated_at', 
            bqType: 'TIMESTAMP', 
            sqliteType: 'TEXT NOT NULL', 
            description: '更新日時 (ISO8601)',
            nullable: false,
        },
    ],
    
    // インデックス定義
    indexes: [
        { name: 'idx_events_date', columns: ['date'] },
        { name: 'idx_events_hole', columns: ['hole'] },
        { name: 'idx_events_event', columns: ['event'] },
        { name: 'idx_events_date_hole', columns: ['date', 'hole'] },
    ],
    
    /**
     * BigQuery用スキーマを生成
     * @returns {Array} BigQueryスキーマ配列
     */
    toBigQuerySchema() {
        return this.columns.map(col => ({
            name: col.name,
            type: col.bqType,
            description: col.description,
        }));
    },
    
    /**
     * SQLite CREATE TABLE文を生成
     * @param {string} tableName - テーブル名（オプション）
     * @returns {string} CREATE TABLE文
     */
    toSQLiteCreateTable(tableName = 'events') {
        const cols = this.columns.map(col => `    ${col.name} ${col.sqliteType}`).join(',\n');
        return `CREATE TABLE IF NOT EXISTS ${tableName} (\n${cols}\n)`;
    },
    
    /**
     * インデックス作成文を生成
     * @param {string} tableName - テーブル名（オプション）
     * @returns {string[]} CREATE INDEX文の配列
     */
    toSQLiteIndexes(tableName = 'events') {
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
     * 必須カラムの一覧を取得
     * @returns {Array<string>} 必須カラム名配列
     */
    getRequiredColumns() {
        return this.columns.filter(col => !col.nullable).map(col => col.name);
    },
};

export default EVENTS_SCHEMA;
