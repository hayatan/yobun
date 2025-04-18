import puppeteer from 'puppeteer';
import config from '../../config/slorepo-config.js';
import { cleanNumber, calculateMaxMY, calculateMaxMDia } from '../../util/slorepo.js';

export default async function scrapeSlotDataByMachine(date, holeCode, interval = 3000) {
    const hole = config.holes.find(h => h.code === holeCode);
    if (!hole) throw new Error('指定された店舗コードが見つかりません。');

    const urlDate = date.replace(/[-/]/g, '');
    const baseUrl = `https://www.slorepo.com/hole/${holeCode}/${urlDate}/`;
    console.log(`[${date}][${hole.name}] スクレイピングを開始します... ${baseUrl}`);
    const browser = await puppeteer.launch({
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });

    const page = await browser.newPage();
    const allData = [];

    try {
        await new Promise(resolve => setTimeout(resolve, interval));
        console.log(`[${date}][${hole.name}] 機種一覧を取得中...`);
        await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });

        const machines = await getMachines(page);
        console.log(`[${date}][${hole.name}] 機種一覧 (${machines.length}) を取得しました。`);

        for (const [index, machine] of machines.entries()) {
            await new Promise(resolve => setTimeout(resolve, interval));
            console.log(`[${date}][${hole.name}] 機種 ${index + 1}/${machines.length}: ${machine.name} を処理中...`);

            const url = `${baseUrl}kishu/?kishu=${machine.encodedName}`;
            const machineData = await scrapeMachineHtmlData(page, url, date, hole.name, decodeURIComponent(machine.encodedName));
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
        maxMY: calculateMaxMY(item.graphData),
        maxMDia: calculateMaxMDia(item.graphData),
        win: cleanNumber(item.diff) >= 1 ? 1 : 0,
        win1000: cleanNumber(item.diff) >= 1000 ? 1 : 0,
        win2000: cleanNumber(item.diff) >= 2000 ? 1 : 0,
        win5000: cleanNumber(item.diff) >= 5000 ? 1 : 0,
        win7000: cleanNumber(item.diff) >= 7000 ? 1 : 0,
        win10000: cleanNumber(item.diff) >= 10000 ? 1 : 0,
    }));
}

async function getMachines(page) {
    return await page.evaluate(() => {
        const machineLinks = Array.from(document.querySelectorAll('a[href^="kishu/?kishu="]'));
        return machineLinks.map(link => ({
            name: link.textContent.trim(),
            encodedName: link.href.split('kishu/?kishu=')[1]
        }));
    });
}

async function scrapeMachineHtmlData(page, url, date, holeName, machineName) {
    
    page.on("response", async response => {
        const status = response.status();
        if (status >= 400) {
            const method = response.request().method();
            const url = response.url();
            console.log(`[${date}][${holeName}] 機種: ${machineName} の取得に失敗しました。 status=${status} method=${method} url=${url}`);
        }
    });

    await page.goto(url, { waitUntil: 'domcontentloaded' });

    return await page.evaluate((date, holeName, machineName) => {
        const rows = [];
        const slotDivs = document.querySelectorAll('.wp-block-column.is-vertically-aligned-top');

        // グラフデータ付きの部分から抽出
        slotDivs.forEach(div => {
            const pTag = div.querySelector('p.has-text-align-center strong font');
            const table = div.querySelector('table tbody');
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
        const slotTables = document.querySelectorAll('table.table2');
        slotTables.forEach(table => {
            const tbody = table.querySelector('tbody');
            const trs = tbody.querySelectorAll('tr');

            const headers = Array.from(trs[0].querySelectorAll('th')).map(th => th.textContent.trim());

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
                        existingRow.combinedRate =  tds[headers.indexOf('合成')].textContent.trim();
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
    }, date, holeName, machineName);
} 