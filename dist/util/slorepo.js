// 数値の整形
export function cleanNumber(value) {
    return parseInt(value.replace(/,/g, '').replace(/^\+/, ''));
}
// 最大MYの計算
export function calculateMaxMY(graphData) {
    let maxMY = 0, minVal = 0;
    graphData.forEach(value => {
        maxMY = Math.max(maxMY, value - minVal);
        minVal = Math.min(minVal, value);
    });
    return maxMY;
}
// 最大MDiaの計算
export function calculateMaxMDia(graphData) {
    let maxMDia = 0, maxVal = 0;
    graphData.forEach(value => {
        maxMDia = Math.max(maxMDia, maxVal - value);
        maxVal = Math.max(maxVal, value);
    });
    return maxMDia;
}
