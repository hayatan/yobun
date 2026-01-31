# 開発コマンド一覧

## Docker関連（必須）
```bash
# イメージビルド
make build

# サーバー起動（Webダッシュボード）
make run-docker
# ブラウザで http://localhost:8080 にアクセス

# シェル起動（デバッグ用）
make shell
```

## Job実行（Cloud Run Jobs互換）
```bash
# 優先店舗のみスクレイピング
make run-job-priority

# 全店舗の未取得分をスクレイピング
make run-job-normal

# 全店舗強制スクレイピング（テスト用）
make run-job-all
```

## システムユーティリティ（Linux）
```bash
# ファイル操作
ls -la
cd <directory>

# 検索
grep -r "pattern" .
find . -name "*.js"
rg "pattern"  # ripgrep推奨

# Git
git status
git log --oneline -10
git diff
```

## コマンド一覧表示
```bash
make help
```

## 注意事項
- **ローカル直接実行は非推奨** - 必ずDockerを使用
- 環境変数は`.env.production`で設定
- 認証情報は`credentials/`に配置