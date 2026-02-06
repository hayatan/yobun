/**
 * 汎用CSV → ヒートマップレイアウトJSON v2.0 変換スクリプト
 *
 * CSVファイルを読み込み、ヒートマップレイアウトJSON（v2.0）を生成する。
 * フロア分割ロジックは含まない。フロアごとに変換する場合は --machine-filter + --trim-cols で
 * 複数回実行する（スキル csv-to-layout が自動でオーケストレーション可能）。
 *
 * 使い方:
 *   node scripts/parse-layout-csv.js <CSVファイル> --hole <店舗名> --floor <フロア名> [OPTIONS]
 *
 * オプション:
 *   --output <path>           出力ファイルパス（省略時: stdout）
 *   --skip-col <n>            先頭スキップ列数（デフォルト: 1）
 *   --machine-filter <min-max> 台番号範囲フィルタ（例: "2000-2999"）
 *   --trim-cols               フィルタ後の列範囲に切り詰め、列を0始まりに正規化
 *   --description <text>      カスタム説明文
 *   --dry-run                 統計のみ表示、JSON出力しない
 *
 * 例:
 *   node scripts/parse-layout-csv.js data.csv --hole "エスパス秋葉原駅前店" --floor ALL --output out.json
 *   node scripts/parse-layout-csv.js data.csv --hole "エスパス秋葉原駅前店" --floor 2F \
 *     --machine-filter 2000-2999 --trim-cols --output out-2f.json
 */

import fs from 'fs';
import path from 'path';

// --- 構造物キーワード → subtype マッピング ---
// parse-layout-excel.js のキーワードを統合
const STRUCTURE_TYPES = {
    'エスカレーター': 'escalator',
    'ＥＳ': 'escalator',
    'ES': 'escalator',
    '階段': 'stairs',
    'カウンター': 'counter',
    '精算機': 'counter',
    'POS': 'counter',
    'MC': 'counter',
    'ロッカー': 'locker',
    '自販機': 'vending',
    '柱': 'pillar',
    '棚': 'shelf',
    'WC': 'restroom',
    'トイレ': 'restroom',
    '入口': 'entrance',
    '出口': 'entrance',
    'ATM': 'other',
};

// --- CLI引数パーサー ---

function parseCliArgs() {
    const args = process.argv.slice(2);
    const opts = {
        csvPath: null,
        hole: null,
        floor: null,
        output: null,
        skipCol: 1,
        machineFilter: null, // { min, max }
        trimCols: false,
        description: null,
        dryRun: false,
    };

    let i = 0;
    while (i < args.length) {
        const arg = args[i];
        switch (arg) {
            case '--hole':
                opts.hole = args[++i];
                break;
            case '--floor':
                opts.floor = args[++i];
                break;
            case '--output':
                opts.output = args[++i];
                break;
            case '--skip-col':
                opts.skipCol = parseInt(args[++i], 10);
                break;
            case '--machine-filter': {
                const parts = args[++i].split('-');
                opts.machineFilter = { min: parseInt(parts[0], 10), max: parseInt(parts[1], 10) };
                break;
            }
            case '--trim-cols':
                opts.trimCols = true;
                break;
            case '--description':
                opts.description = args[++i];
                break;
            case '--dry-run':
                opts.dryRun = true;
                break;
            case '--help':
                printUsage();
                process.exit(0);
                break;
            default:
                if (!arg.startsWith('-') && !opts.csvPath) {
                    opts.csvPath = arg;
                } else {
                    console.error(`不明なオプション: ${arg}`);
                    printUsage();
                    process.exit(1);
                }
        }
        i++;
    }

    if (!opts.csvPath || !opts.hole || !opts.floor) {
        console.error('エラー: CSVファイルパス、--hole、--floor は必須です。');
        printUsage();
        process.exit(1);
    }

    return opts;
}

function printUsage() {
    console.error(`
使い方: node scripts/parse-layout-csv.js <CSVファイル> --hole <店舗名> --floor <フロア名> [OPTIONS]

必須:
  <CSVファイル>              入力CSVファイルパス
  --hole <name>             店舗正式名称
  --floor <name>            フロア名（例: "2F", "ALL"）

オプション:
  --output <path>           出力ファイルパス（省略時: stdout）
  --skip-col <n>            先頭スキップ列数（デフォルト: 1）
  --machine-filter <min-max> 台番号範囲フィルタ（例: "2000-2999"）
  --trim-cols               フィルタ後の列範囲に切り詰め、列を0始まりに正規化
  --description <text>      カスタム説明文
  --dry-run                 統計のみ表示、JSON出力しない
  --help                    このヘルプを表示
    `.trim());
}

// --- CSV パーサー ---

function parseCsv(content) {
    const lines = content.split(/\r?\n/).filter((line) => line.length > 0);
    return lines.map((line) => line.split(',').map((f) => f.trim()));
}

// --- セル分類 ---

function classifyCell(value) {
    const trimmed = String(value ?? '').trim();
    if (trimmed === '') return null;

    const machineMatch = trimmed.match(/^(\d{3,4})$/);
    if (machineMatch) {
        const num = parseInt(machineMatch[1], 10);
        if (num >= 100 && num <= 9999) {
            return { type: 'machine', number: num };
        }
    }

    for (const [keyword, subtype] of Object.entries(STRUCTURE_TYPES)) {
        if (trimmed.includes(keyword)) {
            return { type: 'structure', subtype, label: trimmed };
        }
    }

    return { type: 'label', text: trimmed };
}

// --- セル収集 ---

function collectCells(rows, skipCols) {
    const cells = [];
    const numRows = rows.length;
    let numCols = 0;
    for (const row of rows) {
        if (row.length > numCols) numCols = row.length;
    }
    const gridCols = Math.max(0, numCols - skipCols);

    for (let r = 0; r < numRows; r++) {
        const row = rows[r];
        for (let c = skipCols; c < row.length; c++) {
            const layoutCol = c - skipCols;
            const classified = classifyCell(row[c]);
            if (!classified) continue;
            cells.push({ row: r, col: layoutCol, ...classified });
        }
    }

    return { cells, numRows, gridCols };
}

// --- 台番号フィルタ ---

function filterByMachineRange(cells, min, max) {
    return cells.filter((cell) => {
        if (cell.type !== 'machine') return true; // 構造物・ラベルは保持
        return cell.number >= min && cell.number <= max;
    });
}

// --- 列トリム ---
// 台番号セルの列範囲を基準に、範囲外のセルを除外し、列を0始まりに正規化

function trimColumns(cells) {
    const machineCells = cells.filter((c) => c.type === 'machine');
    if (machineCells.length === 0) return { cells: [], gridCols: 0, colOffset: 0 };

    let minCol = Infinity;
    let maxCol = -Infinity;
    for (const cell of machineCells) {
        if (cell.col < minCol) minCol = cell.col;
        if (cell.col > maxCol) maxCol = cell.col;
    }

    const colOffset = minCol;
    const gridCols = maxCol - minCol + 1;
    // 台番号の列範囲外にある非台番号セルも除外
    const trimmedCells = cells
        .filter((c) => c.col >= minCol && c.col <= maxCol)
        .map((c) => ({ ...c, col: c.col - colOffset }));

    return { cells: trimmedCells, gridCols, colOffset };
}

// --- レイアウト出力形式 ---

function toLayoutCell(cell) {
    const base = { row: cell.row, col: cell.col };
    if (cell.type === 'machine') {
        return { ...base, type: 'machine', number: cell.number };
    }
    if (cell.type === 'structure') {
        return { ...base, type: 'structure', subtype: cell.subtype, label: cell.label };
    }
    return { ...base, type: 'label', text: cell.text };
}

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

// --- メイン ---

const opts = parseCliArgs();

console.error(`読み込み中: ${opts.csvPath}`);
const content = fs.readFileSync(opts.csvPath, 'utf-8');
const rows = parseCsv(content);
let { cells, numRows, gridCols } = collectCells(rows, opts.skipCol);

console.error(`行数: ${numRows}, グリッド列数: ${gridCols} (スキップ列: ${opts.skipCol})`);

const totalMachines = cells.filter((c) => c.type === 'machine').length;
const totalStructures = cells.filter((c) => c.type === 'structure').length;
const totalLabels = cells.filter((c) => c.type === 'label').length;
console.error(`セル数: ${cells.length} (台: ${totalMachines}, 構造物: ${totalStructures}, ラベル: ${totalLabels})`);

// 台番号フィルタ
if (opts.machineFilter) {
    const before = cells.length;
    cells = filterByMachineRange(cells, opts.machineFilter.min, opts.machineFilter.max);
    const filteredMachines = cells.filter((c) => c.type === 'machine').length;
    console.error(`台番号フィルタ: ${opts.machineFilter.min}-${opts.machineFilter.max} → 台: ${filteredMachines}, 全セル: ${cells.length} (${before - cells.length} 除外)`);
}

// 列トリム
if (opts.trimCols) {
    const result = trimColumns(cells);
    cells = result.cells;
    gridCols = result.gridCols;
    console.error(`列トリム: offset=${result.colOffset}, gridCols=${gridCols}`);
}

if (opts.dryRun) {
    console.error('\n[dry-run] ファイル出力をスキップしました。');
    process.exit(0);
}

// レイアウト生成
const description = opts.description || `CSV「${path.basename(opts.csvPath)}」から自動生成（${opts.floor}）`;
const layout = buildLayout(opts.hole, opts.floor, numRows, gridCols, cells, description);

const json = JSON.stringify(layout, null, 2);

if (opts.output) {
    const outputDir = path.dirname(opts.output);
    fs.mkdirSync(outputDir, { recursive: true });
    fs.writeFileSync(opts.output, json);
    console.error(`出力: ${opts.output} (${layout.cells.length} セル)`);
} else {
    process.stdout.write(json + '\n');
}

console.error('完了.');
