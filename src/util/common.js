// 指定した時間だけ待機
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// データのバリデーション
const validateDiffData = (data) => {
    return data.every(row =>
        row.date && row.hole && row.machine &&
        !isNaN(parseInt(row.game, 10)) &&
        !isNaN(parseInt(row.machine_number, 10)) &&
        !isNaN(parseInt(row.diff, 10))
    );
};

// データを整形
const formatDiffData = (data) => {
    return data.map(row => ({
        date: row.date.replace(/\//g, '-'),
        hole: row.hole,
        machine: row.machine,
        machine_number: parseInt(row.machine_number || row.machineNumber, 10),
        diff: parseInt(row.diff, 10),
        game: parseInt(row.game, 10),
        big: parseInt(row.big, 10),
        reg: parseInt(row.reg, 10),
        combined_rate: row.combined_rate || row.combinedRate,
        max_my: parseInt(row.max_my || row.maxMY, 10),
        max_mdia: parseInt(row.max_mdia || row.maxMDia, 10),
        win: parseInt(row.win, 10),
    }))
};

const util = {
    delay,
    validateDiffData,
    formatDiffData,
};

export default util;