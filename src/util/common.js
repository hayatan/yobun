// 開始日から終了日までの日付を生成
export function generateDateRange(startDate, endDate) {
    const dates = [];
    let currentDate = new Date(startDate);
  
    while (currentDate <= new Date(endDate)) {
      dates.push(formatDate(currentDate));
      currentDate.setDate(currentDate.getDate() + 1);
    }
  
    return dates;
};

// 指定した時間だけ待機
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export function formatUrlDate(date) {
    const d = new Date(date);
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}${month}${day}`;
}

function formatDate(date) {
    const d = new Date(date);
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

// データのバリデーション
const validateDiffData = (data) => {
    return data.every(row =>
        row.date && row.hole && row.machine &&
        parseInt(row.game, 10) !== null &&
        parseInt(row.game, 10) !== undefined &&
        parseInt(row.machine_number, 10) !== null &&
        parseInt(row.machine_number, 10) !== undefined &&
        parseInt(row.diff, 10) !== null &&
        parseInt(row.diff, 10) !== undefined
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

export function getDefaultDateRange() {
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - 7);
    const endDate = new Date();
    return { startDate, endDate };
}

const util = {
    generateDateRange,
    delay,
    validateDiffData,
    formatDiffData,
    formatUrlDate,
    getDefaultDateRange,
};

export default util;