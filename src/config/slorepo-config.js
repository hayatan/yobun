// ============================================================================
// 店舗設定
// ============================================================================
// 
// スロレポで対応している店舗の設定
// priority: 'high' = 特化店舗（優先処理）, 'normal' = 通常, 'low' = 低優先度
// region: 地域分類
// active: スクレイピング対象かどうか
// lateUpdate: 情報反映が遅い店舗（1日複数回スクレイピング対象）
// ============================================================================

const config = {
    holes: [
        {
            name: "アイランド秋葉原店",
            code: 'e382a2e382a4e383a9e383b3e38389e7a78be89189e58e9fe5ba97code',
            priority: 'high',
            region: '秋葉原',
            active: true,
            lateUpdate: true,
        },
        {
            name: "エスパス秋葉原駅前店",
            code: 'e382a8e382b9e38391e382b9e697a5e68b93e7a78be89189e58e9fe9a785e5898de5ba97code',
            priority: 'high',
            region: '秋葉原',
            active: true,
            lateUpdate: true,
        },
        {
            name: "ビッグアップル秋葉原店",
            code: 'e38393e38383e382b0e382a2e38383e38397e383abefbc8ee7a78be89189e58e9fe5ba97code',
            priority: 'normal',
            region: '秋葉原',
            active: true,
            lateUpdate: false,
        },
        {
            name: "秋葉原UNO",
            code: 'e7a78be89189e58e9f554e4fcode',
            priority: 'normal',
            region: '秋葉原',
            active: true,
            lateUpdate: false,
        },
        {
            name: "エスパス上野本館",
            code: 'e382a8e382b9e38391e382b9e697a5e68b93e4b88ae9878ee69cace9a4a8code',
            priority: 'normal',
            region: '上野',
            active: true,
            lateUpdate: false,
        },
        {
            name: "三ノ輪ＵＮＯ",
            code: 'e4b889e3838ee8bcaa554e4fcode',
            priority: 'low',
            region: 'その他',
            active: true,
            lateUpdate: false,
        },
        {
            name: "マルハン新宿東宝ビル店",
            code: 'e3839ee383abe3838fe383b3e696b0e5aebfe69db1e5ae9de38393e383abe5ba97code',
            priority: 'normal',
            region: '新宿',
            active: true,
            lateUpdate: false,
        },
        {
            name: "マルハン鹿浜店",
            code: 'e3839ee383abe3838fe383b3e9b9bfe6b59ce5ba97code',
            priority: 'low',
            region: 'その他',
            active: true,
            lateUpdate: false,
        },
        {
            name: "ジュラク王子店",
            code: 'e382b8e383a5e383a9e382afe78e8be5ad90e5ba97code',
            priority: 'low',
            region: 'その他',
            active: true,
            lateUpdate: false,
        },
        {
            name: "メッセ竹の塚",
            code: 'e383a1e38383e382bbe7abb9e381aee5a19ae5ba97code',
            priority: 'low',
            region: 'その他',
            active: true,
            lateUpdate: false,
        },
        {
            name: "ニュークラウン綾瀬店",
            code: 'e3838be383a5e383bce382afe383a9e382a6e383b3e7b6bee780ace5ba97code',
            priority: 'low',
            region: 'その他',
            active: true,
            lateUpdate: false,
        },
        {
            name: "タイヨーネオ富山店",
            code: 'e382bfe382a4e383a8e383bce3838de382aae5af8ce5b1b1e5ba97code',
            priority: 'low',
            region: '富山',
            active: true,
            lateUpdate: false,
        },
        {
            name: "KEIZ富山田中店",
            code: '4b45495ae5af8ce5b1b1e794b0e4b8ade5ba97code',
            priority: 'low',
            region: '富山',
            active: true,
            lateUpdate: false,
        },
    ]
};

// ============================================================================
// ヘルパー関数
// ============================================================================

/**
 * 条件に合う店舗を取得
 * @param {Object} filter - フィルタ条件
 * @param {string} filter.priority - 優先度 ('high' | 'normal' | 'low')
 * @param {string} filter.region - 地域
 * @param {boolean} filter.active - アクティブのみ
 * @param {boolean} filter.lateUpdate - 情報反映が遅い店舗のみ
 * @returns {Array} フィルタされた店舗リスト
 */
export const getHoles = (filter = {}) => {
    let holes = config.holes;
    
    // デフォルトでactiveのみ
    if (filter.active !== false) {
        holes = holes.filter(h => h.active);
    }
    
    if (filter.priority) {
        holes = holes.filter(h => h.priority === filter.priority);
    }
    
    if (filter.region) {
        holes = holes.filter(h => h.region === filter.region);
    }
    
    if (filter.lateUpdate !== undefined) {
        holes = holes.filter(h => h.lateUpdate === filter.lateUpdate);
    }
    
    return holes;
};

/**
 * 優先度順にソートされた店舗リストを取得
 * @returns {Array} 優先度順にソートされた店舗リスト（high -> normal -> low）
 */
export const getHolesSortedByPriority = () => {
    const priorityOrder = { 'high': 0, 'normal': 1, 'low': 2 };
    return getHoles().sort((a, b) => priorityOrder[a.priority] - priorityOrder[b.priority]);
};

/**
 * 高優先度の店舗のみ取得
 * @returns {Array} 高優先度店舗リスト
 */
export const getHighPriorityHoles = () => getHoles({ priority: 'high' });

/**
 * 店舗コードから店舗を検索
 * @param {string} code - 店舗コード
 * @returns {Object|undefined} 店舗オブジェクト
 */
export const findHoleByCode = (code) => config.holes.find(h => h.code === code);

/**
 * 店舗名から店舗を検索
 * @param {string} name - 店舗名
 * @returns {Object|undefined} 店舗オブジェクト
 */
export const findHoleByName = (name) => config.holes.find(h => h.name === name);

export default config;
