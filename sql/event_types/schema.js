// ============================================================================
// イベントタイプスキーマ定義（SQLiteのみ）
// ============================================================================
// 
// イベント種類のマスターデータを管理するテーブルのスキーマ
// フロントエンドの選択肢表示に使用
// BigQuery同期は不要（分析には使用しない）
// 
// 使用方法:
//   import { EVENT_TYPES_SCHEMA } from '../../sql/event_types/schema.js';
//   const sqliteCreate = EVENT_TYPES_SCHEMA.toSQLiteCreateTable();
// ============================================================================

import crypto from 'crypto';

export const EVENT_TYPES_SCHEMA = {
    // スキーマバージョン（変更時にインクリメント）
    version: '1.0.0',
    
    // テーブル名
    tableName: 'event_types',
    
    // カラム定義
    columns: [
        { 
            name: 'id', 
            sqliteType: 'TEXT PRIMARY KEY', 
            description: 'ユニークID (UUID)',
            nullable: false,
        },
        { 
            name: 'name', 
            sqliteType: 'TEXT NOT NULL UNIQUE', 
            description: 'イベント名 (LINE告知、特定日など)',
            nullable: false,
        },
        { 
            name: 'sort_order', 
            sqliteType: 'INTEGER NOT NULL DEFAULT 0', 
            description: '表示順',
            nullable: false,
            default: 0,
        },
        { 
            name: 'created_at', 
            sqliteType: 'TEXT NOT NULL', 
            description: '作成日時 (ISO8601)',
            nullable: false,
        },
    ],
    
    // インデックス定義
    indexes: [
        { name: 'idx_event_types_name', columns: ['name'] },
        { name: 'idx_event_types_sort_order', columns: ['sort_order'] },
    ],
    
    /**
     * SQLite CREATE TABLE文を生成
     * @param {string} tableName - テーブル名（オプション）
     * @returns {string} CREATE TABLE文
     */
    toSQLiteCreateTable(tableName = 'event_types') {
        const cols = this.columns.map(col => `    ${col.name} ${col.sqliteType}`).join(',\n');
        return `CREATE TABLE IF NOT EXISTS ${tableName} (\n${cols}\n)`;
    },
    
    /**
     * インデックス作成文を生成
     * @param {string} tableName - テーブル名（オプション）
     * @returns {string[]} CREATE INDEX文の配列
     */
    toSQLiteIndexes(tableName = 'event_types') {
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
};

export default EVENT_TYPES_SCHEMA;
