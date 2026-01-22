// ============================================================================
// 手動補正データスキーマ定義
// ============================================================================
// 
// 手動で補正したデータを永続化するテーブルのスキーマ
// scraped_data と同じデータカラム + メタ情報を持つ
// 再取得時のフォールバック用データとして使用
// 
// 使用方法:
//   import { MANUAL_CORRECTIONS_SCHEMA } from '../../sql/manual_corrections/schema.js';
//   const sqliteCreate = MANUAL_CORRECTIONS_SCHEMA.toSQLiteCreateTable();
// ============================================================================

import crypto from 'crypto';

export const MANUAL_CORRECTIONS_SCHEMA = {
    // スキーマバージョン（変更時にインクリメント）
    version: '1.0.0',
    
    // テーブル名
    tableName: 'manual_corrections',
    
    // カラム定義（scraped_data と同じ + メタ情報）
    columns: [
        // === scraped_data と同じカラム ===
        { 
            name: 'id', 
            sqliteType: 'TEXT PRIMARY KEY', 
            description: 'ユニークID: {date}_{hole}_{machine_number}_{source}',
            nullable: false,
        },
        { 
            name: 'date', 
            sqliteType: 'TEXT NOT NULL', 
            description: '日付 (YYYY-MM-DD)',
            nullable: false,
        },
        { 
            name: 'hole', 
            sqliteType: 'TEXT NOT NULL', 
            description: '店舗名',
            nullable: false,
        },
        { 
            name: 'machine', 
            sqliteType: 'TEXT NOT NULL', 
            description: '機種名',
            nullable: false,
        },
        { 
            name: 'machine_number', 
            sqliteType: 'INTEGER NOT NULL', 
            description: '台番',
            nullable: false,
        },
        { 
            name: 'diff', 
            sqliteType: 'INTEGER', 
            description: '差枚',
            nullable: true,
        },
        { 
            name: 'game', 
            sqliteType: 'INTEGER', 
            description: 'ゲーム数',
            nullable: true,
        },
        { 
            name: 'big', 
            sqliteType: 'INTEGER', 
            description: 'BB回数',
            nullable: true,
        },
        { 
            name: 'reg', 
            sqliteType: 'INTEGER', 
            description: 'RB回数',
            nullable: true,
        },
        { 
            name: 'combined_rate', 
            sqliteType: 'TEXT', 
            description: '合成確率',
            nullable: true,
        },
        { 
            name: 'max_my', 
            sqliteType: 'INTEGER', 
            description: 'MAX MY（未使用、0固定）',
            nullable: true,
        },
        { 
            name: 'max_mdia', 
            sqliteType: 'INTEGER', 
            description: 'MAX Mダイヤ（未使用、0固定）',
            nullable: true,
        },
        { 
            name: 'win', 
            sqliteType: 'INTEGER', 
            description: '勝敗フラグ (1=勝ち, 0=負け)',
            nullable: true,
        },
        { 
            name: 'source', 
            sqliteType: 'TEXT NOT NULL DEFAULT \'slorepo\'', 
            description: 'データソース (slorepo, minrepo等)',
            nullable: false,
            default: 'slorepo',
        },
        { 
            name: 'timestamp', 
            sqliteType: 'TEXT NOT NULL', 
            description: 'レコード作成日時',
            nullable: false,
        },
        // === メタ情報カラム ===
        { 
            name: 'failure_id', 
            sqliteType: 'TEXT', 
            description: '元の失敗レコードID (scrape_failures.id)',
            nullable: true,
        },
        { 
            name: 'corrected_at', 
            sqliteType: 'TEXT NOT NULL', 
            description: '補正日時 (ISO8601)',
            nullable: false,
        },
        { 
            name: 'notes', 
            sqliteType: 'TEXT', 
            description: '補正時のメモ',
            nullable: true,
        },
    ],
    
    // インデックス定義
    indexes: [
        { name: 'idx_corrections_date', columns: ['date'] },
        { name: 'idx_corrections_hole', columns: ['hole'] },
        { name: 'idx_corrections_date_hole', columns: ['date', 'hole'] },
        { name: 'idx_corrections_failure_id', columns: ['failure_id'] },
    ],
    
    /**
     * SQLite CREATE TABLE文を生成
     * @param {string} tableName - テーブル名（オプション）
     * @returns {string} CREATE TABLE文
     */
    toSQLiteCreateTable(tableName = 'manual_corrections') {
        const cols = this.columns.map(col => `    ${col.name} ${col.sqliteType}`).join(',\n');
        return `CREATE TABLE IF NOT EXISTS ${tableName} (\n${cols}\n)`;
    },
    
    /**
     * インデックス作成文を生成
     * @param {string} tableName - テーブル名（オプション）
     * @returns {string[]} CREATE INDEX文の配列
     */
    toSQLiteIndexes(tableName = 'manual_corrections') {
        return this.indexes.map(idx => 
            `CREATE INDEX IF NOT EXISTS ${idx.name} ON ${tableName} (${idx.columns.join(', ')})`
        );
    },
    
    /**
     * ID生成（scraped_dataと同じ形式）
     * @param {string} date - 日付
     * @param {string} hole - 店舗名
     * @param {number} machineNumber - 台番
     * @param {string} source - データソース
     * @returns {string} ユニークID
     */
    generateId(date, hole, machineNumber, source = 'slorepo') {
        return `${date}_${hole}_${machineNumber}_${source}`;
    },
    
    /**
     * カラム名の一覧を取得
     * @returns {Array<string>} カラム名配列
     */
    getColumnNames() {
        return this.columns.map(col => col.name);
    },
    
    /**
     * scraped_data互換のカラム名を取得（メタ情報を除く）
     * @returns {Array<string>} カラム名配列
     */
    getScrapedDataColumns() {
        const metaColumns = ['failure_id', 'corrected_at', 'notes'];
        return this.columns
            .filter(col => !metaColumns.includes(col.name))
            .map(col => col.name);
    },
};

export default MANUAL_CORRECTIONS_SCHEMA;
