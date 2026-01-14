// ============================================================================
// slorepo データソース設定
// ============================================================================
// 
// スロレポからのスクレイピングに必要な設定を定義
// URL構築、DOMセレクタ、Puppeteer設定など
// ============================================================================

export const SLOREPO_SOURCE = {
    // データソース識別子
    name: 'slorepo',
    
    // ベースURL
    baseUrl: 'https://www.slorepo.com',
    
    // URL構築関数
    buildUrl: {
        // 店舗ページURL: /hole/{holeCode}/{YYYYMMDD}/
        hole: (holeCode, date) => {
            const urlDate = date.replace(/[-/]/g, '');
            return `https://www.slorepo.com/hole/${holeCode}/${urlDate}/`;
        },
        // 機種ページURL: /hole/{holeCode}/{YYYYMMDD}/kishu/?kishu={encodedMachine}
        machine: (holeCode, date, encodedMachine) => {
            const urlDate = date.replace(/[-/]/g, '');
            return `https://www.slorepo.com/hole/${holeCode}/${urlDate}/kishu/?kishu=${encodedMachine}`;
        },
    },
    
    // DOMセレクタ
    selectors: {
        // 機種リンク一覧
        machineLinks: 'a[href^="kishu/?kishu="]',
        // スロットデータのコンテナ
        slotDivs: '.wp-block-column.is-vertically-aligned-top',
        // 台番表示
        machineNumber: 'p.has-text-align-center strong font',
        // データテーブル
        dataTable: 'table tbody',
        // 一覧テーブル
        summaryTable: 'table.table2',
    },
    
    // テーブルの必須ヘッダー
    requiredHeaders: ['台番', '差枚', 'G数', 'BB', 'RB', '合成'],
    
    // ヘッダー名のマッピング（日本語 -> フィールド名）
    headerMapping: {
        '台番': 'machineNumber',
        '差枚': 'diff',
        'G数': 'game',
        'BB': 'big',
        'RB': 'reg',
        '合成': 'combinedRate',
    },
    
    // Puppeteer設定
    puppeteer: {
        headless: true,
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-blink-features=AutomationControlled',
        ],
    },
    
    // User-Agent（bot検出回避用）
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
    
    // ページ遷移オプション
    navigation: {
        waitUntil: 'domcontentloaded',
    },
};

export default SLOREPO_SOURCE;
