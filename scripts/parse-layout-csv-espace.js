/**
 * エスパス秋葉原のCSVフロアマップをヒートマップレイアウトJSONに変換するスクリプト
 *
 * 入力CSV: 1列目は行ラベル、2列目以降がグリッド。2F(2000番台)/3F(3000番台)/4F(4000番台)が同一シートにマッピング。
 * 出力: レイアウト v2.0 形式のJSONを4種類
 *   - ALL: 全フロアを1つのグリッドにしたレイアウト（フロア名 "ALL"）
 *   - 2F, 3F, 4F: 各フロアのみのレイアウト（列範囲で切り出し）
 *
 * 使い方:
 *   node scripts/parse-layout-csv-espace.js <CSVファイル> [出力ディレクトリ]
 *
 * 例:
 *   node scripts/parse-layout-csv-espace.js ".temporaly/YoBun_エスパス秋葉原_直近28日 - HM補正 のコピー.csv" ./layouts-espace
 */

import fs from 'fs';
import path from 'path';

const HOLE_NAME = 'エスパス秋葉原駅前店';

const csvPath = process.argv[2];
const outputDir = process.argv[3];

if (!csvPath) {
    console.error('使い方: node scripts/parse-layout-csv-espace.js <CSVファイル> [出力ディレクトリ]');
    process.exit(1);
}

/**
 * 台番号からフロアを判定（2xxx→2F, 3xxx→3F, 4xxx→4F）
 */
function floorFromMachineNumber(num) {
    if (num >= 2000 && num <= 2999) return '2F';
    if (num >= 3000 && num <= 3999) return '3F';
    if (num >= 4000 && num <= 4999) return '4F';
    return null;
}

/**
 * CSVをパースして行の配列（各要素は列の配列）に
 */
function parseCsv(content) {
    const lines = content.split(/\r?\n/).filter((line) => line.length > 0);
    return lines.map((line) => line.split(',').map((f) => f.trim()));
}

/**
 * グリッドセルを収集（1列目は行ラベルのためスキップ、col は 0 始まりでデータ列のみ）
 */
function collectCells(rows) {
    const cells = [];
    const numRows = rows.length;
    let numCols = 0;
    for (const row of rows) {
        if (row.length > numCols) numCols = row.length;
    }
    // グリッド: 行 0..numRows-1, 列 0..numCols-2（CSVの列1がlayoutの列0）
    const gridCols = Math.max(0, numCols - 1);

    for (let r = 0; r < numRows; r++) {
        const row = rows[r];
        for (let c = 1; c < row.length; c++) {
            const layoutCol = c - 1;
            const value = String(row[c] ?? '').trim();
            if (value === '') continue;

            const machineMatch = value.match(/^(\d{3,4})$/);
            if (machineMatch) {
                const num = parseInt(machineMatch[1], 10);
                const floor = floorFromMachineNumber(num);
                if (floor && num >= 2000 && num <= 4999) {
                    cells.push({
                        row: r,
                        col: layoutCol,
                        type: 'machine',
                        number: num,
                        floor,
                    });
                }
                continue;
            }

            if (value === '階段') {
                cells.push({
                    row: r,
                    col: layoutCol,
                    type: 'structure',
                    subtype: 'stairs',
                    label: value,
                    floor: null, // 後で列範囲から割り当て
                });
                continue;
            }

            // その他（☆など）はラベルとして扱う
            cells.push({
                row: r,
                col: layoutCol,
                type: 'label',
                text: value,
                floor: null,
            });
        }
    }

    return { cells, numRows, gridCols };
}

/**
 * フロアごとの列範囲を計算（台番号が出現する列の min/max）
 */
function getFloorColumnRanges(cells) {
    const ranges = { '2F': { min: Infinity, max: -Infinity }, '3F': { min: Infinity, max: -Infinity }, '4F': { min: Infinity, max: -Infinity } };
    for (const cell of cells) {
        if (cell.type === 'machine' && cell.floor) {
            const r = ranges[cell.floor];
            if (cell.col < r.min) r.min = cell.col;
            if (cell.col > r.max) r.max = cell.col;
        }
    }
    for (const f of ['2F', '3F', '4F']) {
        if (ranges[f].min === Infinity) ranges[f].min = 0;
        if (ranges[f].max === -Infinity) ranges[f].max = 0;
    }
    return ranges;
}

/**
 * 列が指定フロアの列範囲に含まれるか
 */
function colInFloor(col, floor, ranges) {
    const r = ranges[floor];
    return col >= r.min && col <= r.max;
}

/**
 * フロア未割り当てのセルにフロアを付与（列が複数フロアにまたがる場合はALL用のみに含め、各フロア用には列範囲で含める）
 */
function assignFloorToNonMachineCells(cells, ranges) {
    for (const cell of cells) {
        if (cell.floor != null) continue;
        if (colInFloor(cell.col, '2F', ranges)) cell.floor = '2F';
        else if (colInFloor(cell.col, '3F', ranges)) cell.floor = '3F';
        else if (colInFloor(cell.col, '4F', ranges)) cell.floor = '4F';
    }
}

/**
 * セルをレイアウトv2.0の cell 形式に変換（row/col はそのまま、type/number/label 等）
 */
function toLayoutCell(c) {
    const base = { row: c.row, col: c.col };
    if (c.type === 'machine') {
        return { ...base, type: 'machine', number: c.number };
    }
    if (c.type === 'structure') {
        return { ...base, type: 'structure', subtype: c.subtype, label: c.label };
    }
    return { ...base, type: 'label', text: c.text };
}

/**
 * レイアウトオブジェクトを生成
 */
function buildLayout(hole, floor, gridRows, gridCols, cells, description) {
    return {
        version: '2.0',
        hole,
        floor,
        updated: new Date().toISOString().split('T')[0],
        description: description || '',
        grid: { rows: gridRows, cols: gridCols },
        walls: [],
        cells: cells.map(toLayoutCell),
    };
}

// --- 実行 ---
console.log(`読み込み中: ${csvPath}`);
const content = fs.readFileSync(csvPath, 'utf-8');
const rows = parseCsv(content);
const { cells, numRows, gridCols } = collectCells(rows);

const ranges = getFloorColumnRanges(cells);
assignFloorToNonMachineCells(cells, ranges);

console.log(`行数: ${numRows}, 列数: ${gridCols}`);
console.log('フロア別列範囲:', ranges);
console.log(`セル数: ${cells.length} (台: ${cells.filter((c) => c.type === 'machine').length}, 構造物等: ${cells.filter((c) => c.type !== 'machine').length})`);

// ALL: 全セル
const allCells = cells.map((c) => ({ ...c }));
const layoutAll = buildLayout(
    HOLE_NAME,
    'ALL',
    numRows,
    gridCols,
    allCells,
    `CSV「${path.basename(csvPath)}」から自動生成（全フロア）`
);

// 2F / 3F / 4F: 各フロアの列範囲でフィルタし、col を 0 始まりに正規化
const floorLayouts = [
    { floor: '2F', range: ranges['2F'] },
    { floor: '3F', range: ranges['3F'] },
    { floor: '4F', range: ranges['4F'] },
];

const layouts = [{ floor: 'ALL', layout: layoutAll }];

for (const { floor, range } of floorLayouts) {
    const colMin = range.min;
    const colMax = range.max;
    const floorCols = colMax - colMin + 1;
    const floorCells = cells
        .filter((c) => c.floor === floor)
        .map((c) => ({
            ...c,
            row: c.row,
            col: c.col - colMin,
        }))
        .map((c) => ({ ...c, floor: undefined })); // 出力には不要
    const layout = buildLayout(
        HOLE_NAME,
        floor,
        numRows,
        floorCols,
        floorCells,
        `CSV「${path.basename(csvPath)}」から自動生成（${floor}）`
    );
    layouts.push({ floor, layout });
}

if (outputDir) {
    fs.mkdirSync(outputDir, { recursive: true });
    const slug = (f) => (f === 'ALL' ? 'all' : f.toLowerCase());
    for (const { floor, layout } of layouts) {
        const filename = `espace-akihabara-${slug(layout.floor)}.json`;
        const outPath = path.join(outputDir, filename);
        fs.writeFileSync(outPath, JSON.stringify(layout, null, 2));
        console.log(`出力: ${outPath} (${layout.cells.length} セル)`);
    }
} else {
    console.log('\n--- 出力ディレクトリを指定するとJSONファイルが保存されます ---');
    console.log('例: node scripts/parse-layout-csv-espace.js "..." ./layouts-espace\n');
    console.log('--- ALL レイアウト（先頭のみ） ---');
    console.log(JSON.stringify(layoutAll, null, 2).slice(0, 1500) + '...');
}

console.log('\n完了.');
