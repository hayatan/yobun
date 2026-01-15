/**
 * JST（日本標準時）ベースの日付ユーティリティ
 * 
 * Cloud Run（UTC）でもローカル環境でも、日本時間基準で日付を扱う
 */

const JST_OFFSET_MS = 9 * 60 * 60 * 1000; // UTC+9

/**
 * JST基準で日付を取得
 * @param {number} daysOffset - 日付オフセット（0=今日、-1=昨日）
 * @returns {string} YYYY-MM-DD形式の日付文字列
 */
export const getJSTDate = (daysOffset = 0) => {
    const now = new Date();
    const jst = new Date(now.getTime() + JST_OFFSET_MS);
    jst.setDate(jst.getDate() + daysOffset);
    return jst.toISOString().split('T')[0];
};

/**
 * JST基準で昨日の日付を取得
 * @returns {string} YYYY-MM-DD形式の日付文字列
 */
export const getJSTYesterday = () => getJSTDate(-1);

/**
 * JST基準で今日の日付を取得
 * @returns {string} YYYY-MM-DD形式の日付文字列
 */
export const getJSTToday = () => getJSTDate(0);

/**
 * JST基準で現在時刻を取得
 * @returns {Date} JST時刻のDateオブジェクト
 */
export const getJSTNow = () => {
    return new Date(Date.now() + JST_OFFSET_MS);
};

/**
 * JST基準で現在時刻を HH:MM 形式で取得
 * @returns {string} HH:MM形式の時刻文字列
 */
export const getJSTTimeString = () => {
    const jst = getJSTNow();
    const hours = jst.getUTCHours().toString().padStart(2, '0');
    const minutes = jst.getUTCMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
};

/**
 * 日付文字列をURL用フォーマット（YYYYMMDD）に変換
 * @param {string} dateStr - YYYY-MM-DD形式の日付文字列
 * @returns {string} YYYYMMDD形式の日付文字列
 */
export const formatUrlDate = (dateStr) => {
    return dateStr.replace(/-/g, '');
};

/**
 * 日付範囲を生成
 * @param {Date|string} startDate - 開始日
 * @param {Date|string} endDate - 終了日
 * @returns {string[]} YYYY-MM-DD形式の日付文字列の配列
 */
export const generateDateRange = (startDate, endDate) => {
    const start = new Date(startDate);
    const end = new Date(endDate);
    const dates = [];
    
    const current = new Date(start);
    while (current <= end) {
        dates.push(current.toISOString().split('T')[0]);
        current.setDate(current.getDate() + 1);
    }
    
    return dates;
};

export default {
    getJSTDate,
    getJSTYesterday,
    getJSTToday,
    getJSTNow,
    getJSTTimeString,
    formatUrlDate,
    generateDateRange,
};
