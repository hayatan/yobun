/**
 * ヒートマップレイアウトのGCSストレージ（マルチフロア対応）
 *
 * gs://youbun-sqlite/layouts/{hole-slug}/{floor-slug}.json に保存
 * ローカルファイルは廃止（GCS のみ）
 */

import { Storage } from '@google-cloud/storage';

const storage = new Storage();
const BUCKET_NAME = 'youbun-sqlite';
const LAYOUTS_PREFIX = 'layouts/';

/**
 * 店舗名からGCSディレクトリ名用スラグを生成（拡張子なし）
 */
export const holeToSlug = (hole) => {
    const mapping = {
        'アイランド秋葉原店': 'island-akihabara',
        'エスパス秋葉原駅前店': 'espace-akihabara',
        'ビッグアップル秋葉原店': 'bigapple-akihabara',
        '秋葉原UNO': 'uno-akihabara',
        'エスパス上野本館': 'espace-ueno',
        '三ノ輪ＵＮＯ': 'uno-minowa',
        'マルハン新宿東宝ビル店': 'maruhan-shinjuku',
        'マルハン鹿浜店': 'maruhan-shikahama',
        'ジュラク王子店': 'juraku-oji',
        'メッセ竹の塚': 'messe-takenotsuka',
        'ニュークラウン綾瀬店': 'newcrown-ayase',
        'タイヨーネオ富山店': 'taiyoneo-toyama',
        'KEIZ富山田中店': 'keiz-toyama',
    };
    if (mapping[hole]) return mapping[hole];
    return encodeURIComponent(hole).replace(/%/g, '-').toLowerCase();
};

/**
 * フロア名をファイル名安全な文字列に変換（例: "1F" -> "1f"）
 */
export const floorToSlug = (floor) => {
    if (!floor || typeof floor !== 'string') return '1f';
    return floor
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9_-]/g, '-')
        .replace(/-+/g, '-')
        .replace(/^-|-$/g, '') || '1f';
};

/**
 * GCSパスを組み立て
 */
const getGcsPath = (hole, floor) => {
    const slug = holeToSlug(hole);
    const floorSlug = floorToSlug(floor);
    return `${LAYOUTS_PREFIX}${slug}/${floorSlug}.json`;
};

/**
 * レイアウトを読み込み（GCSのみ）
 */
export const loadLayout = async (hole, floor) => {
    const gcsPath = getGcsPath(hole, floor);
    try {
        const bucket = storage.bucket(BUCKET_NAME);
        const file = bucket.file(gcsPath);

        const [exists] = await file.exists();
        if (!exists) {
            return { layout: null };
        }

        const [content] = await file.download();
        const layout = JSON.parse(content.toString());
        if (!layout.floor) layout.floor = floor || '1F';
        if (!layout.version) layout.version = '1.0';
        console.log(`[GCS] レイアウト読み込み成功: ${gcsPath}`);
        return { layout };
    } catch (error) {
        console.error(`[GCS] レイアウト読み込みエラー: ${gcsPath}`, error.message);
        return { layout: null };
    }
};

/**
 * レイアウトをGCSに保存
 */
export const saveLayout = async (hole, floor, layout) => {
    const gcsPath = getGcsPath(hole, floor);
    try {
        const bucket = storage.bucket(BUCKET_NAME);
        const file = bucket.file(gcsPath);

        layout.updated = new Date().toISOString().split('T')[0];
        layout.hole = hole;
        layout.floor = floor || '1F';
        if (!layout.version) layout.version = '2.0';

        await file.save(JSON.stringify(layout, null, 2), {
            contentType: 'application/json',
        });

        console.log(`[GCS] レイアウト保存成功: ${gcsPath}`);
        return { success: true, filename: `${holeToSlug(hole)}/${floorToSlug(floor)}.json` };
    } catch (error) {
        console.error(`[GCS] レイアウト保存エラー: ${gcsPath}`, error.message);
        throw error;
    }
};

/**
 * レイアウト一覧を取得（GCSのみ、全 layout に floor を含む）
 * パス: layouts/{slug}/{floor-slug}.json のみ対象（フラットな旧形式は含めない）
 */
export const listLayouts = async () => {
    try {
        const bucket = storage.bucket(BUCKET_NAME);
        const [files] = await bucket.getFiles({ prefix: LAYOUTS_PREFIX });

        const layouts = [];
        for (const file of files) {
            const name = file.name;
            if (!name.endsWith('.json') || name.includes('_template')) continue;
            const parts = name.slice(LAYOUTS_PREFIX.length).split('/');
            if (parts.length !== 2) continue;

            try {
                const [content] = await file.download();
                const layout = JSON.parse(content.toString());
                layouts.push({
                    filename: name,
                    hole: layout.hole,
                    floor: layout.floor || '1F',
                    version: layout.version,
                    updated: layout.updated,
                    description: layout.description,
                    cellCount: layout.cells?.length || 0,
                });
            } catch (e) {
                console.warn(`GCSレイアウトパースエラー: ${name}`, e.message);
            }
        }
        return layouts;
    } catch (error) {
        console.error('GCSレイアウト一覧取得エラー:', error.message);
        return [];
    }
};

/**
 * 特定店舗のフロア一覧を取得
 */
export const listFloors = async (hole) => {
    const slug = holeToSlug(hole);
    const prefix = `${LAYOUTS_PREFIX}${slug}/`;
    try {
        const bucket = storage.bucket(BUCKET_NAME);
        const [files] = await bucket.getFiles({ prefix });

        const floors = [];
        for (const file of files) {
            if (!file.name.endsWith('.json')) continue;
            try {
                const [content] = await file.download();
                const layout = JSON.parse(content.toString());
                const floor = layout.floor || '1F';
                if (!floors.includes(floor)) floors.push(floor);
            } catch (e) {
                console.warn(`GCSレイアウトパースエラー: ${file.name}`, e.message);
            }
        }
        return floors.sort();
    } catch (error) {
        console.error('GCSフロア一覧取得エラー:', error.message);
        return [];
    }
};

/**
 * レイアウトが存在するか
 */
export const layoutExists = async (hole, floor) => {
    const gcsPath = getGcsPath(hole, floor);
    try {
        const bucket = storage.bucket(BUCKET_NAME);
        const file = bucket.file(gcsPath);
        const [exists] = await file.exists();
        return exists;
    } catch (error) {
        return false;
    }
};

/**
 * レイアウトを削除
 */
export const deleteLayout = async (hole, floor) => {
    const gcsPath = getGcsPath(hole, floor);
    try {
        const bucket = storage.bucket(BUCKET_NAME);
        const file = bucket.file(gcsPath);
        const [exists] = await file.exists();
        if (!exists) {
            return { success: false, error: 'レイアウトが存在しません' };
        }
        await file.delete();
        console.log(`[GCS] レイアウト削除: ${gcsPath}`);
        return { success: true };
    } catch (error) {
        console.error(`[GCS] レイアウト削除エラー: ${gcsPath}`, error.message);
        throw error;
    }
};

export default {
    holeToSlug,
    floorToSlug,
    loadLayout,
    saveLayout,
    listLayouts,
    listFloors,
    layoutExists,
    deleteLayout,
};
