// ============================================================================
// 元データスキーマ定義（SQLite/BigQuery共用）
// ============================================================================
// 
// スクレイピングで取得した元データのスキーマを一元管理
// SQLiteとBigQuery両方で使用できる形式で定義
// 
// 使用方法:
//   import { RAW_DATA_SCHEMA } from '../../sql/raw_data/schema.js';
//   const bqSchema = RAW_DATA_SCHEMA.toBigQuerySchema();
//   const sqliteCreate = RAW_DATA_SCHEMA.toSQLiteCreateTable('scraped_data');
// ============================================================================

export const RAW_DATA_SCHEMA = {
    // スキーマバージョン（変更時にインクリメント）
    version: '2.0.0',
    
    // カラム定義
    columns: [
        { 
            name: 'id', 
            bqType: 'STRING', 
            sqliteType: 'TEXT PRIMARY KEY', 
            description: 'ユニークID: {date}_{hole}_{machine_number}_{source}',
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
            name: 'machine', 
            bqType: 'STRING', 
            sqliteType: 'TEXT NOT NULL', 
            description: '機種名',
            nullable: false,
        },
        { 
            name: 'machine_number', 
            bqType: 'INTEGER', 
            sqliteType: 'INTEGER NOT NULL', 
            description: '台番',
            nullable: false,
        },
        { 
            name: 'diff', 
            bqType: 'INTEGER', 
            sqliteType: 'INTEGER', 
            description: '差枚',
            nullable: true,
        },
        { 
            name: 'game', 
            bqType: 'INTEGER', 
            sqliteType: 'INTEGER', 
            description: 'ゲーム数',
            nullable: true,
        },
        { 
            name: 'big', 
            bqType: 'INTEGER', 
            sqliteType: 'INTEGER', 
            description: 'BB回数',
            nullable: true,
        },
        { 
            name: 'reg', 
            bqType: 'INTEGER', 
            sqliteType: 'INTEGER', 
            description: 'RB回数',
            nullable: true,
        },
        { 
            name: 'combined_rate', 
            bqType: 'STRING', 
            sqliteType: 'TEXT', 
            description: '合成確率',
            nullable: true,
        },
        { 
            name: 'max_my', 
            bqType: 'INTEGER', 
            sqliteType: 'INTEGER', 
            description: 'MAX MY（未使用、0固定）',
            nullable: true,
        },
        { 
            name: 'max_mdia', 
            bqType: 'INTEGER', 
            sqliteType: 'INTEGER', 
            description: 'MAX Mダイヤ（未使用、0固定）',
            nullable: true,
        },
        { 
            name: 'win', 
            bqType: 'INTEGER', 
            sqliteType: 'INTEGER', 
            description: '勝敗フラグ (1=勝ち, 0=負け)',
            nullable: true,
        },
        { 
            name: 'source', 
            bqType: 'STRING', 
            sqliteType: 'TEXT NOT NULL DEFAULT \'slorepo\'', 
            description: 'データソース (slorepo, minrepo等)',
            nullable: false,
            default: 'slorepo',
        },
        { 
            name: 'timestamp', 
            bqType: 'TIMESTAMP', 
            sqliteType: 'TEXT NOT NULL', 
            description: 'レコード作成日時',
            nullable: false,
        },
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
     * @param {string} tableName - テーブル名
     * @returns {string} CREATE TABLE文
     */
    toSQLiteCreateTable(tableName = 'scraped_data') {
        const cols = this.columns.map(col => `    ${col.name} ${col.sqliteType}`).join(',\n');
        return `CREATE TABLE IF NOT EXISTS ${tableName} (\n${cols}\n)`;
    },
    
    /**
     * ID生成（複数ソース対応）
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
     * 必須カラムの一覧を取得
     * @returns {Array<string>} 必須カラム名配列
     */
    getRequiredColumns() {
        return this.columns.filter(col => !col.nullable).map(col => col.name);
    },
};

export default RAW_DATA_SCHEMA;
