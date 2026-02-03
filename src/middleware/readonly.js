/**
 * 読み取り専用モードのミドルウェア
 * 
 * 環境変数 READONLY_MODE=true で有効化
 * 書き込み操作（POST/PUT/PATCH/DELETE）をブロックし、Web公開版として安全に運用
 */

const READONLY_MODE = process.env.READONLY_MODE === 'true';

// 書き込みを伴わないPOSTエンドポイント（ホワイトリスト）
const READONLY_ALLOWED_POSTS = [
    '/api/corrections/parse',  // パース処理のみ、DB操作なし
];

/**
 * 読み取り専用モードのミドルウェア
 * POST/PUT/PATCH/DELETEをブロック（ホワイトリスト除く）
 */
export const readonlyMiddleware = (req, res, next) => {
    if (!READONLY_MODE) return next();

    const method = req.method;
    const path = req.path;

    // GETは常に許可
    if (method === 'GET') return next();

    // ホワイトリストにあるPOSTは許可
    if (method === 'POST' && READONLY_ALLOWED_POSTS.includes(path)) {
        return next();
    }

    // その他の書き込み操作は拒否
    if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(method)) {
        return res.status(403).json({
            error: 'Forbidden',
            message: '読み取り専用モードでは書き込み操作は許可されていません',
            readonly: true,
        });
    }

    next();
};

/**
 * 読み取り専用モードかどうかを返す
 * @returns {boolean}
 */
export const isReadonlyMode = () => READONLY_MODE;

export default {
    readonlyMiddleware,
    isReadonlyMode,
};
