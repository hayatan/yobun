# コードスタイルと規約

## モジュール
- ES6モジュールを使用
- ファイル拡張子`.js`を明示的に指定
```javascript
import module from './module.js';
export default function() { ... }
```

## ファイル命名規則
- スネークケース (`snake_case`) またはケバブケース (`kebab-case`)
- 例: `slorepo-config.js`, `state-manager.js`

## 非同期処理
- `async/await`を基本とする
- エラーハンドリングは`try/catch`で統一

## ログ出力
- 日付とホール名を明示的に表示
```javascript
console.log(`[${date}][${hole.name}] 機種 ${index + 1}/${machines.length}: ${machine.name} を処理中...`);
```

## 設定管理
- 環境変数は`dotenv`で管理
- 定数は`src/config/constants.js`に集約
- 店舗設定は`src/config/slorepo-config.js`に集約

## スキーマ管理
- Single Source of Truth: `sql/raw_data/schema.js`
- SQLiteとBigQuery両方のスキーマを生成

## Git コミットメッセージ
- **日本語**で記述
- プレフィックスを使用:
  - `[追加]` - 新機能
  - `[修正]` - バグ修正
  - `[変更]` - 既存機能の変更
  - `[削除]` - 削除
  - `[リファクタ]` - リファクタリング
  - `[ドキュメント]` - ドキュメント更新