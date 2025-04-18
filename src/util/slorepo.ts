// 数値の整形
export function cleanNumber(value: string): number {
    return parseInt(value.replace(/,/g, '').replace(/^\+/, ''));
}

// 最大MYの計算
export function calculateMaxMY(graphData: number[]): number {
    let maxMY = 0, minVal = 0;
    graphData.forEach(value => {
        maxMY = Math.max(maxMY, value - minVal);
        minVal = Math.min(minVal, value);
    });
    return maxMY;
}

// 最大MDiaの計算
export function calculateMaxMDia(graphData: number[]): number {
    let maxMDia = 0, maxVal = 0;
    graphData.forEach(value => {
        maxMDia = Math.max(maxMDia, maxVal - value);
        maxVal = Math.max(maxVal, value);
    });
    return maxMDia;
} 