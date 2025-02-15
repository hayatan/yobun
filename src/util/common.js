// 開始日から終了日までの日付を生成
const generateDateRange = (startDate, endDate) => {
    const start = new Date(startDate);
    const end = new Date(endDate);
    const dateArray = [];
  
    while (start <= end) {
      // フォーマットを 'YYYY-MM-DD' にする
      const year = start.getFullYear();
      const month = String(start.getMonth() + 1).padStart(2, '0');
      const day = String(start.getDate()).padStart(2, '0');
  
      dateArray.push(`${year}-${month}-${day}`);
      start.setDate(start.getDate() + 1); // 次の日に進む
    }
  
    return dateArray;
};

// 指定した時間だけ待機
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const formatUrlDate = (date) => date.replace(/[-/]/g, '');

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

module.exports = {
    generateDateRange,
    delay,
    validateDiffData,
    formatDiffData,
    formatUrlDate,
};