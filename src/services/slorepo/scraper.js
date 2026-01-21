import puppeteer from 'puppeteer-extra';
import StealthPlugin from 'puppeteer-extra-plugin-stealth';
import config from '../../config/slorepo-config.js';
import { SLOREPO_SOURCE } from '../../config/sources/slorepo.js';
import { cleanNumber } from '../../util/slorepo.js';

// Cloudflare等のボット検出を回避するためのStealthプラグインを使用
puppeteer.use(StealthPlugin());

/**
 * スクレイピングエラーの種別を判定
 * @param {Error} error - エラーオブジェクト
 * @param {string} [pageTitle] - ページタイトル（Cloudflare判定用）
 * @returns {string} エラー種別
 */
export function classifyError(error, pageTitle = '') {
    const message = error.message || '';
    const title = pageTitle.toLowerCase();
    
    // Cloudflare関連
    if (title.includes('cloudflare') || 
        title.includes('just a moment') || 
        title.includes('checking') ||
        message.includes('cloudflare')) {
        return 'cloudflare';
    }
    
    // タイムアウト
    if (message.includes('timeout') || 
        message.includes('Timeout') ||
        message.includes('Navigation timeout')) {
        return 'timeout';
    }
    
    // ネットワークエラー
    if (message.includes('net::') || 
        message.includes('ECONNREFUSED') ||
        message.includes('ENOTFOUND') ||
        message.includes('network')) {
        return 'network';
    }
    
    // パースエラー
    if (message.includes('parse') || 
        message.includes('undefined') ||
        message.includes('null') ||
        message.includes('Cannot read')) {
        return 'parse';
    }
    
    return 'unknown';
}

/**
 * ブラウザの初期化（ボット検出回避設定込み）
 */
async function initBrowser() {
    const browser = await puppeteer.launch({
        headless: SLOREPO_SOURCE.puppeteer.headless,
        args: SLOREPO_SOURCE.puppeteer.args,
    });

    const page = await browser.newPage();
    
    // ビューポート設定（自然なブラウザに見せる）
    await page.setViewport({
        width: 1920,
        height: 1080,
        deviceScaleFactor: 1,
    });
    
    // User-Agentを設定
    await page.setUserAgent(SLOREPO_SOURCE.userAgent);
    
    // 追加のボット検出回避設定
    await page.setExtraHTTPHeaders({
        'Accept-Language': 'ja-JP,ja;q=0.9,en-US;q=0.8,en;q=0.7',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Cache-Control': 'max-age=0',
    });
    
    // webdriver プロパティを削除
    await page.evaluateOnNewDocument(() => {
        Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    });

    return { browser, page };
}

/**
 * Cloudflareチャレンジを処理
 */
async function handleCloudflareChallenge(page, date, holeName) {
    let pageTitle = await page.title();
    const cloudflareIndicators = ['Just a moment', 'Checking', 'しばらくお待ちください', 'Cloudflare'];
    const isCloudflare = cloudflareIndicators.some(indicator => pageTitle.includes(indicator));
    
    if (isCloudflare) {
        console.log(`[${date}][${holeName}] Cloudflareチャレンジ検出 ("${pageTitle}")、待機中...`);
        try {
            await page.waitForFunction(
                (indicators) => {
                    const title = document.title;
                    return !indicators.some(ind => title.includes(ind));
                },
                { timeout: 60000 },
                cloudflareIndicators
            );
            await new Promise(resolve => setTimeout(resolve, 5000));
            pageTitle = await page.title();
            console.log(`[${date}][${holeName}] Cloudflareチャレンジ通過: "${pageTitle}"`);
        } catch (e) {
            console.log(`[${date}][${holeName}] Cloudflareチャレンジのタイムアウト - 続行を試みます`);
        }
    }
    return pageTitle;
}

/**
 * 機種一覧のみを取得（機種数比較用）
 * @param {string} date - 日付
 * @param {string} holeCode - 店舗コード
 * @param {number} interval - 待機時間（ミリ秒）
 * @returns {Promise<{count: number, machines: Array}>} 機種数と機種一覧
 */
export async function scrapeMachineList(date, holeCode, interval = 1000) {
    const hole = config.holes.find(h => h.code === holeCode);
    if (!hole) throw new Error('指定された店舗コードが見つかりません。');

    const baseUrl = SLOREPO_SOURCE.buildUrl.hole(holeCode, date);
    console.log(`[${date}][${hole.name}] 機種一覧を取得中... ${baseUrl}`);
    
    const { browser, page } = await initBrowser();

    try {
        await new Promise(resolve => setTimeout(resolve, interval));
        await page.goto(baseUrl, { waitUntil: 'networkidle0', timeout: 60000 });

        const pageTitle = await handleCloudflareChallenge(page, date, hole.name);
        
        const pageUrl = page.url();
        console.log(`[${date}][${hole.name}] ページロード完了 - タイトル: "${pageTitle}", URL: ${pageUrl}`);

        const machines = await getMachines(page, SLOREPO_SOURCE.selectors.machineLinks);
        console.log(`[${date}][${hole.name}] 機種一覧 (${machines.length}) を取得しました。`);

        return {
            count: machines.length,
            machines: machines.map(m => m.name),
        };
    } finally {
        await browser.close();
    }
}

/**
 * 機種別スロットデータのスクレイピング
 * @param {string} date - 日付
 * @param {string} holeCode - 店舗コード
 * @param {number} interval - 待機時間（ミリ秒）
 * @returns {Promise<{data: Array, failures: Array}>} データと機種レベルの失敗情報
 */
export default async function scrapeSlotDataByMachine(date, holeCode, interval = 1000) {
    const hole = config.holes.find(h => h.code === holeCode);
    if (!hole) throw new Error('指定された店舗コードが見つかりません。');

    const baseUrl = SLOREPO_SOURCE.buildUrl.hole(holeCode, date);
    console.log(`[${date}][${hole.name}] スクレイピングを開始します... ${baseUrl}`);
    
    const { browser, page } = await initBrowser();
    const allData = [];
    const machineFailures = []; // 機種レベルの失敗を収集

    try {
        await new Promise(resolve => setTimeout(resolve, interval));
        console.log(`[${date}][${hole.name}] 機種一覧を取得中...`);
        await page.goto(baseUrl, { waitUntil: 'networkidle0', timeout: 60000 });

        const pageTitle = await handleCloudflareChallenge(page, date, hole.name);

        // デバッグ: ページ情報を出力
        const pageUrl = page.url();
        console.log(`[${date}][${hole.name}] ページロード完了 - タイトル: "${pageTitle}", URL: ${pageUrl}`);
        
        // デバッグ: 機種リンクのセレクタをチェック
        const allLinks = await page.evaluate(() => {
            const links = Array.from(document.querySelectorAll('a'));
            return links.filter(l => l.href.includes('kishu')).map(l => ({ href: l.href, text: l.textContent.trim() })).slice(0, 5);
        });
        console.log(`[${date}][${hole.name}] kishuリンク候補 (最大5件):`, JSON.stringify(allLinks));

        const machines = await getMachines(page, SLOREPO_SOURCE.selectors.machineLinks);
        console.log(`[${date}][${hole.name}] 機種一覧 (${machines.length}) を取得しました。`);

        for (const [index, machine] of machines.entries()) {
            await new Promise(resolve => setTimeout(resolve, interval));
            console.log(`[${date}][${hole.name}] 機種 ${index + 1}/${machines.length}: ${machine.name} を処理中...`);

            const url = SLOREPO_SOURCE.buildUrl.machine(holeCode, date, machine.encodedName);
            const result = await scrapeMachineHtmlData(page, url, date, hole.name, decodeURIComponent(machine.encodedName), SLOREPO_SOURCE);
            
            // データを追加
            if (result.data && result.data.length > 0) {
                allData.push(...result.data);
            }
            
            // 失敗情報を収集（HTTPエラーの場合のみ）
            if (result.error) {
                machineFailures.push({
                    machine: decodeURIComponent(machine.encodedName),
                    url,
                    errorType: classifyHttpError(result.error.status),
                    message: result.error.message,
                    status: result.error.status,
                });
            }

            console.log(`[${date}][${hole.name}] 機種 ${index + 1}/${machines.length}: ${machine.name} の処理が完了しました。`);
        }

        // データの整形とMYおよびMDiaの計算をここで実施
        const processedData = processSlotData(allData);

        // 失敗があった場合はログ出力
        if (machineFailures.length > 0) {
            console.log(`[${date}][${hole.name}] 機種レベルの失敗: ${machineFailures.length}件`);
        }

        return {
            data: processedData,
            failures: machineFailures,
        };
    } finally {
        await browser.close();
    }
}

/**
 * HTTPステータスコードからエラー種別を判定
 * @param {number} status - HTTPステータスコード
 * @returns {string} エラー種別
 */
function classifyHttpError(status) {
    if (status === 403) return 'cloudflare';
    if (status === 404) return 'not_found';
    if (status === 429) return 'rate_limit';
    if (status >= 500) return 'server_error';
    if (status >= 400) return 'client_error';
    return 'unknown';
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
    
    // HTTPエラー情報を収集
    let httpError = null;
    
    page.on("response", async response => {
        const status = response.status();
        const responseUrl = response.url();
        
        // メインリクエストのエラーのみを記録（favicon等は除外）
        if (status >= 400 && responseUrl === url) {
            const method = response.request().method();
            console.log(`[${date}][${holeName}] 機種: ${machineName} の取得に失敗しました。 status=${status} method=${method} url=${responseUrl}`);
            httpError = {
                status,
                method,
                url: responseUrl,
                message: `HTTP ${status} エラー`,
            };
        } else if (status >= 400) {
            // その他のリクエスト（favicon等）はログのみ
            const method = response.request().method();
            console.log(`[${date}][${holeName}] 機種: ${machineName} の取得に失敗しました。 status=${status} method=${method} url=${responseUrl}`);
        }
    });

    await page.goto(url, { waitUntil: sourceConfig.navigation.waitUntil });

    const selectors = sourceConfig.selectors;
    const requiredHeaders = sourceConfig.requiredHeaders;
    
    const rows = await page.evaluate((date, holeName, machineName, selectors, requiredHeaders) => {
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
    
    // データとエラー情報を返す
    return { data: rows, error: httpError };
} 