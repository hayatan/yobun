/**
 * Excelファイルからヒートマップレイアウトを生成するスクリプト
 * 
 * 使い方:
 *   node scripts/parse-layout-excel.js <excelファイル> <出力JSONファイル>
 * 
 * 例:
 *   node scripts/parse-layout-excel.js .temporaly/アイランド秋葉原_台番島図251103.xlsx src/config/heatmap-layouts/island-akihabara.json
 */

import XLSX from 'xlsx';
import fs from 'fs';
import path from 'path';

const excelPath = process.argv[2];
const outputPath = process.argv[3];

if (!excelPath) {
    console.error('使い方: node scripts/parse-layout-excel.js <excelファイル> [出力JSONファイル]');
    process.exit(1);
}

// Excelファイルを読み込む
console.log(`読み込み中: ${excelPath}`);
const workbook = XLSX.readFile(excelPath);

// 最初のシートを取得
const sheetName = workbook.SheetNames[0];
const sheet = workbook.Sheets[sheetName];
console.log(`シート名: ${sheetName}`);

// シートの範囲を取得
const range = XLSX.utils.decode_range(sheet['!ref']);
console.log(`範囲: ${sheet['!ref']}`);
console.log(`行: ${range.s.r} - ${range.e.r} (${range.e.r - range.s.r + 1}行)`);
console.log(`列: ${range.s.c} - ${range.e.c} (${range.e.c - range.s.c + 1}列)`);

// 結合セルの情報を取得
const merges = sheet['!merges'] || [];
console.log(`結合セル数: ${merges.length}`);

// 結合セルマップを作成（結合範囲の最初のセル以外はスキップ）
const mergeMap = new Map();
const mergeRoots = new Map(); // 結合セルの起点
merges.forEach(merge => {
    const rootKey = `${merge.s.r}-${merge.s.c}`;
    const rows = merge.e.r - merge.s.r + 1;
    const cols = merge.e.c - merge.s.c + 1;
    mergeRoots.set(rootKey, { rows, cols });
    
    for (let r = merge.s.r; r <= merge.e.r; r++) {
        for (let c = merge.s.c; c <= merge.e.c; c++) {
            if (r !== merge.s.r || c !== merge.s.c) {
                mergeMap.set(`${r}-${c}`, rootKey);
            }
        }
    }
});

// セルデータを収集
const cells = [];
const labelCells = [];

for (let r = range.s.r; r <= range.e.r; r++) {
    for (let c = range.s.c; c <= range.e.c; c++) {
        const key = `${r}-${c}`;
        
        // 結合セルの一部（起点以外）はスキップ
        if (mergeMap.has(key)) {
            continue;
        }
        
        const cellAddress = XLSX.utils.encode_cell({ r, c });
        const cell = sheet[cellAddress];
        
        if (!cell || cell.v === undefined || cell.v === null || cell.v === '') {
            continue;
        }
        
        const value = String(cell.v).trim();
        
        // 台番号かどうか判定（数字3-4桁）
        // 3桁: パチンコ（600-899など）、4桁: スロット（1000-1999など）
        const machineMatch = value.match(/^(\d{3,4})$/);
        if (machineMatch) {
            const num = parseInt(machineMatch[1], 10);
            // 妥当な台番号の範囲をチェック（100-9999）
            if (num >= 100 && num <= 9999) {
                cells.push({
                    row: r,
                    col: c,
                    type: 'machine',
                    number: num
                });
                continue;
            }
        }
        
        // ラベルまたは構造物
        const structureTypes = {
            'エスカレーター': 'escalator',
            'ＥＳ': 'escalator',
            'ES': 'escalator',
            '階段': 'stairs',
            'カウンター': 'counter',
            '精算機': 'counter',
            'ロッカー': 'locker',
            '自販機': 'vending',
            '柱': 'pillar',
            '棚': 'shelf',
            'POS': 'counter',
            'MC': 'counter',
            'WC': 'restroom',
            'トイレ': 'restroom',
            '入口': 'entrance',
            '出口': 'entrance',
            'ATM': 'other',
        };
        
        let cellType = 'label';
        let subtype = null;
        
        for (const [keyword, type] of Object.entries(structureTypes)) {
            if (value.includes(keyword)) {
                if (type === 'label') {
                    cellType = 'label';
                } else {
                    cellType = 'structure';
                    subtype = type;
                }
                break;
            }
        }
        
        const cellData = {
            row: r,
            col: c,
            type: cellType,
        };
        
        if (cellType === 'structure') {
            cellData.subtype = subtype;
            cellData.label = value;
        } else {
            cellData.text = value;
        }
        
        // 結合セルの場合、サイズ情報を追加
        const mergeInfo = mergeRoots.get(key);
        if (mergeInfo) {
            cellData.mergeRows = mergeInfo.rows;
            cellData.mergeCols = mergeInfo.cols;
        }
        
        labelCells.push(cellData);
    }
}

console.log(`\n検出した台数: ${cells.length}`);
console.log(`検出したラベル/構造物: ${labelCells.length}`);

// 台番号の範囲を表示
if (cells.length > 0) {
    const numbers = cells.map(c => c.number).sort((a, b) => a - b);
    console.log(`台番号範囲: ${numbers[0]} - ${numbers[numbers.length - 1]}`);
}

// レイアウトJSONを作成
const layout = {
    version: '1.0',
    hole: 'アイランド秋葉原店',
    updated: new Date().toISOString().split('T')[0],
    description: `${path.basename(excelPath)}から自動生成`,
    grid: {
        rows: range.e.r - range.s.r + 1,
        cols: range.e.c - range.s.c + 1
    },
    walls: [],
    cells: [...cells, ...labelCells].map(c => ({
        ...c,
        row: c.row - range.s.r,  // 0始まりに正規化
        col: c.col - range.s.c
    }))
};

// 出力
if (outputPath) {
    fs.writeFileSync(outputPath, JSON.stringify(layout, null, 2));
    console.log(`\n出力: ${outputPath}`);
} else {
    console.log('\n--- JSON出力 ---');
    console.log(JSON.stringify(layout, null, 2));
}

// 統計情報
console.log('\n--- 統計 ---');
console.log(`グリッドサイズ: ${layout.grid.rows}行 x ${layout.grid.cols}列`);
console.log(`総セル数: ${layout.cells.length}`);
console.log(`  - 台: ${cells.length}`);
console.log(`  - ラベル/構造物: ${labelCells.length}`);

// サンプル出力
console.log('\n--- サンプルセル（最初の10件） ---');
layout.cells.slice(0, 10).forEach(c => {
    if (c.type === 'machine') {
        console.log(`  [${c.row}, ${c.col}] 台番号: ${c.number}`);
    } else if (c.type === 'structure') {
        console.log(`  [${c.row}, ${c.col}] 構造物: ${c.subtype} (${c.label})`);
    } else {
        console.log(`  [${c.row}, ${c.col}] ラベル: ${c.text}`);
    }
});
