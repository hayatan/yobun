/**
 * GCS のレイアウトを旧形式（layouts/{filename}.json）から
 * 新形式（layouts/{hole-slug}/{floor-slug}.json）へコピーするスクリプト
 *
 * 使い方:
 *   node scripts/migrate-layouts-to-floors.js
 *
 * 処理内容:
 * - GCS の layouts/ プレフィックスで全ファイルを列挙
 * - 旧形式（layouts/xxx.json、パスにスラッシュが1つだけ）のファイルを対象に:
 *   - JSON を取得し、floor がなければ "1F" を付与
 *   - 新パス layouts/{hole-slug}/1f.json に保存
 * - 旧ファイルは削除しない（動作確認後に手動削除）
 */

import { Storage } from '@google-cloud/storage';
import layoutStorage from '../src/config/heatmap-layouts/storage.js';

const BUCKET_NAME = 'youbun-sqlite';
const LAYOUTS_PREFIX = 'layouts/';

async function main() {
    const storage = new Storage();
    const bucket = storage.bucket(BUCKET_NAME);
    const [files] = await bucket.getFiles({ prefix: LAYOUTS_PREFIX });

    const oldFormatFiles = files.filter((file) => {
        const name = file.name;
        if (!name.endsWith('.json') || name === LAYOUTS_PREFIX) return false;
        const relative = name.slice(LAYOUTS_PREFIX.length);
        return !relative.includes('/');
    });

    if (oldFormatFiles.length === 0) {
        console.log('移行対象の旧形式レイアウトファイルはありません。');
        return;
    }

    console.log(`移行対象: ${oldFormatFiles.length} 件`);

    for (const file of oldFormatFiles) {
        try {
            const [content] = await file.download();
            const layout = JSON.parse(content.toString());
            const hole = layout.hole;
            if (!hole) {
                console.warn(`スキップ（hole なし）: ${file.name}`);
                continue;
            }
            const floor = layout.floor || '1F';
            layout.floor = floor;
            if (!layout.version) layout.version = '2.0';

            await layoutStorage.saveLayout(hole, floor, layout);
            console.log(`コピー完了: ${file.name} -> layouts/${layoutStorage.holeToSlug(hole)}/${layoutStorage.floorToSlug(floor)}.json`);
        } catch (err) {
            console.error(`エラー: ${file.name}`, err.message);
        }
    }

    console.log('移行処理を完了しました。旧ファイルは残しています。動作確認後に GCS 上で手動削除してください。');
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
