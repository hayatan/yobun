import puppeteer from 'puppeteer';
import config from '../../config/slorepo-config.js';
import { SLOREPO_SOURCE } from '../../config/sources/slorepo.js';
import { cleanNumber } from '../../util/slorepo.js';

export default async function scrapeSlotDataByMachine(date, holeCode, interval = 1000) {
    const hole = config.holes.find(h => h.code === holeCode);
    if (!hole) throw new Error('指定された店舗コードが見つかりません。');

    const baseUrl = SLOREPO_SOURCE.buildUrl.hole(holeCode, date);
    console.log(`[${date}][${hole.name}] スクレイピングを開始します... ${baseUrl}`);
    const browser = await puppeteer.launch({
        headless: SLOREPO_SOURCE.puppeteer.headless,
        args: SLOREPO_SOURCE.puppeteer.args,
    });

    const page = await browser.newPage();
    
    // User-Agentを設定してbot検出を回避
    await page.setUserAgent(SLOREPO_SOURCE.userAgent);
    
    const allData = [];

    try {
        await new Promise(resolve => setTimeout(resolve, interval));
        console.log(`[${date}][${hole.name}] 機種一覧を取得中...`);
        await page.goto(baseUrl, { waitUntil: SLOREPO_SOURCE.navigation.waitUntil });

        const machines = await getMachines(page, SLOREPO_SOURCE.selectors.machineLinks);
        console.log(`[${date}][${hole.name}] 機種一覧 (${machines.length}) を取得しました。`);

        for (const [index, machine] of machines.entries()) {
            await new Promise(resolve => setTimeout(resolve, interval));
            console.log(`[${date}][${hole.name}] 機種 ${index + 1}/${machines.length}: ${machine.name} を処理中...`);

            const url = SLOREPO_SOURCE.buildUrl.machine(holeCode, date, machine.encodedName);
            const machineData = await scrapeMachineHtmlData(page, url, date, hole.name, decodeURIComponent(machine.encodedName), SLOREPO_SOURCE);
            allData.push(...machineData);

            console.log(`[${date}][${hole.name}] 機種 ${index + 1}/${machines.length}: ${machine.name} の処理が完了しました。`);
        }

        // データの整形とMYおよびMDiaの計算をここで実施
        const processedData = processSlotData(allData);

        return processedData;
    } finally {
        await browser.close();
    }
}

// データ処理関数
function processSlotData(allData) {
    return allData.map(item => ({
        ...item,
        diff: cleanNumber(item.diff),
        game: cleanNumber(item.game),
        maxMY: 0,  // 未使用のため0固定
        maxMDia: 0,  // 未使用のため0固定
        win: cleanNumber(item.diff) >= 1 ? 1 : 0,
    }));
}

async function getMachines(page, selector) {
    return await page.evaluate((sel) => {
        const machineLinks = Array.from(document.querySelectorAll(sel));
        return machineLinks.map(link => ({
            name: link.textContent.trim(),
            encodedName: link.href.split('kishu/?kishu=')[1]
        }));
    }, selector);
}

async function scrapeMachineHtmlData(page, url, date, holeName, machineName, sourceConfig) {
    
    // 既存のリスナーを削除してから新しいリスナーを追加
    page.removeAllListeners("response");
    
    page.on("response", async response => {
        const status = response.status();
        if (status >= 400) {
            const method = response.request().method();
            const url = response.url();
            console.log(`[${date}][${holeName}] 機種: ${machineName} の取得に失敗しました。 status=${status} method=${method} url=${url}`);
        }
    });

    await page.goto(url, { waitUntil: sourceConfig.navigation.waitUntil });

    const selectors = sourceConfig.selectors;
    const requiredHeaders = sourceConfig.requiredHeaders;
    
    return await page.evaluate((date, holeName, machineName, selectors, requiredHeaders) => {
        const rows = [];
        const slotDivs = document.querySelectorAll(selectors.slotDivs);

        // グラフデータ付きの部分から抽出
        slotDivs.forEach(div => {
            const pTag = div.querySelector(selectors.machineNumber);
            const table = div.querySelector(selectors.dataTable);
            const scripts = div.querySelectorAll('script');

            let graphData = [];
            scripts.forEach(script => {
                if (script.textContent.includes('data: [')) {
                    const match = script.textContent.match(/data:\s*\[([^\]]*)\]/);
                    if (match && match[1]) graphData = match[1].split(',').map(v => parseInt(v.trim()));
                }
            });

            if (pTag && table) {
                const machineNumber = pTag.textContent.trim();
                const tableRows = table.querySelectorAll('tr');
                if (tableRows.length >= 2) {
                    const headers = Array.from(tableRows[0].querySelectorAll('th')).map(th => th.textContent.trim());
                    const dataRow = tableRows[1].querySelectorAll('td');

                    if (dataRow.length === headers.length) {
                        rows.push({
                            date: date,
                            hole: holeName,
                            machine: machineName,
                            machineNumber,
                            diff: dataRow[headers.indexOf('差枚')].textContent.trim(),
                            game: dataRow[headers.indexOf('G数')].textContent.trim(),
                            big: dataRow[headers.indexOf('BB')].textContent.trim(),
                            reg: dataRow[headers.indexOf('RB')].textContent.trim(),
                            combinedRate: dataRow[headers.indexOf('合成')].textContent.trim(),
                            graphData
                        });
                    }
                }
            }
        });

        // 一覧表から抽出
        const slotTables = document.querySelectorAll(selectors.summaryTable);
        slotTables.forEach(table => {
            // テーブルのヘッダーを確認して、必要なテーブルだけを処理
            const headers = Array.from(table.querySelectorAll('th')).map(th => th.textContent.trim());
            
            // 必要なヘッダーが含まれているか確認
            const hasRequiredHeaders = requiredHeaders.every(header => headers.includes(header));
            
            // 必要なヘッダーが含まれていない場合はスキップ
            if (!hasRequiredHeaders) {
                return;
            }

            const tbody = table.querySelector('tbody');
            const trs = tbody.querySelectorAll('tr');

            trs.forEach(tr => {
                const tds = tr.querySelectorAll('td');

                if (tds.length > 0 && tds[0].textContent.trim() !== '平均') {
                    const machineNumber = tds[headers.indexOf('台番')].textContent.trim();
                    const existingRow = rows.find(row => row.machineNumber === machineNumber);
                    if (existingRow) {
                        existingRow.diff = tds[headers.indexOf('差枚')].textContent.trim();
                        existingRow.game = tds[headers.indexOf('G数')].textContent.trim();
                        existingRow.big = tds[headers.indexOf('BB')].textContent.trim();
                        existingRow.reg = tds[headers.indexOf('RB')].textContent.trim();
                        existingRow.combinedRate = tds[headers.indexOf('合成')].textContent.trim();
                    } else {
                        rows.push({
                            date: date,
                            hole: holeName,
                            machine: machineName,
                            machineNumber,
                            diff: tds[headers.indexOf('差枚')].textContent.trim(),
                            game: tds[headers.indexOf('G数')].textContent.trim(),
                            big: tds[headers.indexOf('BB')].textContent.trim(),
                            reg: tds[headers.indexOf('RB')].textContent.trim(),
                            combinedRate: tds[headers.indexOf('合成')].textContent.trim(),
                            graphData: []
                        });
                    }
                }
            });
        });

        return rows;
    }, date, holeName, machineName, selectors, requiredHeaders);
} 