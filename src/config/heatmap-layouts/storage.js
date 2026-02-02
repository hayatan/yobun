/**
 * ヒートマップレイアウトのGCSストレージ
 * 
 * gs://youbun-sqlite/layouts/{hole}.json に保存
 * ローカルファイルはfallbackとして使用
 */

import { Storage } from '@google-cloud/storage';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const storage = new Storage();
const BUCKET_NAME = 'youbun-sqlite';
const LAYOUTS_PREFIX = 'layouts/';
const LOCAL_DIR = __dirname;

/**
 * 店舗名からファイル名を生成
 */
export const holeToFilename = (hole) => {
    const mapping = {
        'アイランド秋葉原店': 'island-akihabara.json',
        'エスパス秋葉原駅前店': 'espace-akihabara.json',
        'ビッグアップル秋葉原店': 'bigapple-akihabara.json',
        '秋葉原UNO': 'uno-akihabara.json',
        'エスパス上野本館': 'espace-ueno.json',
        '三ノ輪ＵＮＯ': 'uno-minowa.json',
        'マルハン新宿東宝ビル店': 'maruhan-shinjuku.json',
        'マルハン鹿浜店': 'maruhan-shikahama.json',
        'ジュラク王子店': 'juraku-oji.json',
        'メッセ竹の塚': 'messe-takenotsuka.json',
        'ニュークラウン綾瀬店': 'newcrown-ayase.json',
        'タイヨーネオ富山店': 'taiyoneo-toyama.json',
        'KEIZ富山田中店': 'keiz-toyama.json',
    };
    return mapping[hole] || `${hole.replace(/[^a-zA-Z0-9]/g, '-').toLowerCase()}.json`;
};

/**
 * GCSからレイアウトを読み込み
 */
const loadFromGCS = async (filename) => {
    try {
        const bucket = storage.bucket(BUCKET_NAME);
        const file = bucket.file(`${LAYOUTS_PREFIX}${filename}`);
        
        const [exists] = await file.exists();
        if (!exists) {
            return null;
        }
        
        const [content] = await file.download();
        const layout = JSON.parse(content.toString());
        console.log(`[GCS] レイアウト読み込み成功: ${filename}`);
        return layout;
    } catch (error) {
        console.error(`[GCS] レイアウト読み込みエラー: ${filename}`, error.message);
        return null;
    }
};

/**
 * ローカルファイルからレイアウトを読み込み
 */
const loadFromLocal = async (filename) => {
    try {
        const filePath = path.join(LOCAL_DIR, filename);
        const content = await fs.readFile(filePath, 'utf-8');
        const layout = JSON.parse(content);
        console.log(`[Local] レイアウト読み込み成功: ${filename}`);
        return layout;
    } catch (error) {
        if (error.code === 'ENOENT') {
            return null;
        }
        console.error(`[Local] レイアウト読み込みエラー: ${filename}`, error.message);
        return null;
    }
};

/**
 * レイアウトを読み込み（GCS優先、ローカルfallback）
 */
export const loadLayout = async (hole) => {
    const filename = holeToFilename(hole);
    
    // 1. GCSから読み込み
    let layout = await loadFromGCS(filename);
    if (layout) {
        return { layout, source: 'gcs' };
    }
    
    // 2. ローカルから読み込み
    layout = await loadFromLocal(filename);
    if (layout) {
        return { layout, source: 'local' };
    }
    
    return { layout: null, source: null };
};

/**
 * GCSにレイアウトを保存
 */
export const saveLayout = async (hole, layout) => {
    const filename = holeToFilename(hole);
    
    try {
        const bucket = storage.bucket(BUCKET_NAME);
        const file = bucket.file(`${LAYOUTS_PREFIX}${filename}`);
        
        // 更新日時を設定
        layout.updated = new Date().toISOString().split('T')[0];
        
        await file.save(JSON.stringify(layout, null, 2), {
            contentType: 'application/json',
        });
        
        console.log(`[GCS] レイアウト保存成功: ${filename}`);
        return { success: true, filename, source: 'gcs' };
    } catch (error) {
        console.error(`[GCS] レイアウト保存エラー: ${filename}`, error.message);
        throw error;
    }
};

/**
 * GCSからレイアウト一覧を取得
 */
export const listLayoutsFromGCS = async () => {
    try {
        const bucket = storage.bucket(BUCKET_NAME);
        const [files] = await bucket.getFiles({ prefix: LAYOUTS_PREFIX });
        
        const layouts = [];
        for (const file of files) {
            if (file.name.endsWith('.json') && !file.name.includes('_template')) {
                try {
                    const [content] = await file.download();
                    const layout = JSON.parse(content.toString());
                    layouts.push({
                        filename: path.basename(file.name),
                        hole: layout.hole,
                        version: layout.version,
                        updated: layout.updated,
                        description: layout.description,
                        cellCount: layout.cells?.length || 0,
                        source: 'gcs',
                    });
                } catch (e) {
                    console.warn(`GCSレイアウトパースエラー: ${file.name}`, e.message);
                }
            }
        }
        return layouts;
    } catch (error) {
        console.error('GCSレイアウト一覧取得エラー:', error.message);
        return [];
    }
};

/**
 * ローカルからレイアウト一覧を取得
 */
export const listLayoutsFromLocal = async () => {
    try {
        const files = await fs.readdir(LOCAL_DIR);
        const layouts = [];
        
        for (const file of files) {
            if (file.endsWith('.json') && !file.startsWith('_')) {
                try {
                    const filePath = path.join(LOCAL_DIR, file);
                    const content = await fs.readFile(filePath, 'utf-8');
                    const layout = JSON.parse(content);
                    layouts.push({
                        filename: file,
                        hole: layout.hole,
                        version: layout.version,
                        updated: layout.updated,
                        description: layout.description,
                        cellCount: layout.cells?.length || 0,
                        source: 'local',
                    });
                } catch (e) {
                    console.warn(`ローカルレイアウトパースエラー: ${file}`, e.message);
                }
            }
        }
        return layouts;
    } catch (error) {
        console.error('ローカルレイアウト一覧取得エラー:', error.message);
        return [];
    }
};

/**
 * レイアウト一覧を取得（GCS + ローカルをマージ、GCS優先）
 */
export const listLayouts = async () => {
    const [gcsLayouts, localLayouts] = await Promise.all([
        listLayoutsFromGCS(),
        listLayoutsFromLocal(),
    ]);
    
    // GCSとローカルをマージ（GCS優先）
    const layoutMap = new Map();
    
    // まずローカルを追加
    for (const layout of localLayouts) {
        layoutMap.set(layout.hole, layout);
    }
    
    // GCSで上書き
    for (const layout of gcsLayouts) {
        layoutMap.set(layout.hole, layout);
    }
    
    return Array.from(layoutMap.values());
};

export default {
    holeToFilename,
    loadLayout,
    saveLayout,
    listLayouts,
    listLayoutsFromGCS,
    listLayoutsFromLocal,
};
