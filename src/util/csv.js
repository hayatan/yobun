import util from './common.js';
import fs from 'fs';
import csvParser from 'csv-parser';

// CSVファイルを読み込み
export const readCSV = (fileName) => {
    console.log(`CSVファイルを読み込みます: ${fileName}`);
    return new Promise((resolve, reject) => {
        const data = [];
        if (!fs.existsSync(fileName)) {
            return resolve([]); // ファイルが存在しない場合は空配列を返す
        }
        fs.createReadStream(fileName)
            .pipe(csvParser())
            .on('data', (row) => data.push(row))
            .on('end', () => resolve(data))
            .on('error', (error) => reject(error));
    });
};

// CSVファイルに保存
const saveToCSV = (data, fileName) => {

    const formattedData = util.formatDiffData(data);

    if (!util.validateDiffData(formattedData)) {
        throw new Error(`データが不完全なため、CSVへの保存をスキップします: ${fileName}\n${JSON.stringify(formattedData)}`);
    }

    if (formattedData.length === 0) {
        throw new Error(`データが空のため、CSVへの保存をスキップします: ${fileName}`);
    }
    
    // CSV出力用のヘッダー設定
    const keys = [
        'date',
        'hole',
        'machine',
        'machine_number',
        'diff',
        'game',
        'big',
        'reg',
        'combined_rate',
        'max_my',
        'max_mdia',
        'win',
    ];

    // エスケープ処理
    const escapeForCSV = (s) => {
        return typeof s === 'string' ? `"${s.replace(/\"/g, '\"\"')}"` : s
    }

    // CSV作成
    const csvContent = [
        keys.map(h => escapeForCSV(h)).join(','), // ヘッダー
        ...formattedData.map(row =>
            keys.map(k => escapeForCSV(row[k]))
                .join(',')
        )
    ].join('\n');

    fs.writeFileSync(fileName, csvContent, 'utf8');
    console.log(`CSVを保存しました: ${fileName}`);
};

export {
    readCSV,
    saveToCSV,
};