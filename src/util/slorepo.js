// 数値の整形
export function cleanNumber(value) {
    return parseInt(value.replace(/,/g, '').replace(/^\+/, ''));
}

// 注意: calculateMaxMY, calculateMaxMDia は削除
// max_my, max_mdia フィールドは0固定で対応 