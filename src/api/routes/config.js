// ============================================================================
// 設定 ルーター
// ============================================================================
// 
// GET /api/config - フロントエンド用設定を返す
// ============================================================================

import { Router } from 'express';
import { DEFAULT_DATE_RANGES } from '../../config/constants.js';

const router = Router();

// フロントエンド用設定を返すエンドポイント
router.get('/', (req, res) => {
    res.json({
        defaultDateRanges: DEFAULT_DATE_RANGES,
    });
});

export default router;
