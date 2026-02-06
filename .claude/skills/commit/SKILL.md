---
name: commit
description: 差分と作業コンテキストを分析し、Conventional Commits + 絵文字でコミットを作成する
allowed-tools: Bash(git status*), Bash(git diff*), Bash(git log*), Bash(git add *), Bash(git commit *)
argument-hint: [コミットメッセージの補足やスコープ指定]
---

# Git Commit スキル

差分と作業内容のコンテキストを分析し、Conventional Commits 形式 + 絵文字でコミットを作成する。

## コミットメッセージフォーマット

```
type emoij(scope): 説明（日本語）

本文（任意、変更の詳細）

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

- **1行目**: 100文字以内（type + emoji + scope + 説明）
- **本文**: 変更が複雑な場合のみ追加。箇条書きで変更点を列挙
- **scope**: 省略可。影響範囲が明確な場合に付与（例: `heatmap`, `scraper`, `api`, `db`, `scheduler`, `config`, `ui`）

## Type 定義と絵文字

| Type | Emoji | 用途 | 旧形式との対応 |
|------|-------|------|---------------|
| `feat` | ✨ | 新機能の追加 | [追加] |
| `fix` | 🐛 | バグ修正 | [修正] |
| `change` | 🔄 | 既存機能の変更・更新 | [変更] |
| `remove` | 🔥 | コード・ファイル・機能の削除 | [削除] |
| `refactor` | ♻️ | リファクタリング（機能変更なし） | [リファクタリング] |
| `perf` | ⚡ | パフォーマンス改善 | [改善] |
| `docs` | 📝 | ドキュメントのみの変更 | [ドキュメント] |
| `style` | 💄 | コードスタイル変更（機能に影響なし） | - |
| `test` | ✅ | テストの追加・修正 | - |
| `build` | 📦 | ビルドシステム・依存関係の変更 | - |
| `ci` | 👷 | CI/CD 設定の変更 | - |
| `chore` | 🔧 | その他の雑務（設定変更等） | - |
| `revert` | ⏪ | 変更の取り消し | - |

## Type 選択の判断基準

- **feat vs change**: 完全に新しい機能 → `feat`、既存機能の拡張・変更 → `change`
- **fix vs change**: バグの修正 → `fix`、仕様変更 → `change`
- **refactor vs change**: 外部動作が変わらない内部改善 → `refactor`、動作が変わる → `change`
- **perf vs refactor**: パフォーマンス目的 → `perf`、コード品質目的 → `refactor`
- **docs vs chore**: ドキュメントファイルの変更 → `docs`、設定ファイル等 → `chore`
- **BREAKING CHANGE**: `type emoij(scope)!:` のように ! を付与

## 実行手順

1. `git status` で変更ファイルを確認（`-uall` は使わない）
2. `git diff` でステージ済み・未ステージの差分を確認
3. `git log --oneline -5` で直近のコミット履歴を参照
4. 差分の内容を分析し、適切な type・scope・説明を決定
5. ユーザーに提案するコミットメッセージを表示
6. ユーザーの承認後、`git add` でファイルをステージング（機密ファイルを除外）
7. `git commit` でコミットを実行
8. `git status` でコミット結果を確認

## コミットメッセージの例

```
feat ✨(heatmap): レイアウトエディタにJSON直接編集機能を実装
```

```
change 🔄(heatmap): レイアウト管理をGCSのマルチフロア対応に変更

- レイアウトJSONのバージョンを2.0に変更
- 関連APIを更新
- 移行スクリプトを追加
```

```
fix 🐛(scraper): スクレイピング失敗時のリトライ処理を修正
```

```
remove 🔥(deploy): Cloud Build設定を削除
```

```
refactor ♻️(api): エンドポイントをルーターモジュールに分離
```

```
perf ⚡(heatmap): 空間インデックスによるセル検索をO(1)に最適化
```

```
docs 📝: CLAUDE.mdにヒートマップAPI仕様を追加
```

```
chore 🔧(config): MCP サーバー設定を追加
```

```
feat ✨(events)!: イベント管理APIのレスポンス形式を変更

BREAKING CHANGE: events APIのレスポンスにpaginationフィールドを追加
```

## 注意事項

- `.env`、`credentials.json` などの機密ファイルはステージングしない
- 変更と無関係なファイルはコミットに含めない
- ユーザーが `$ARGUMENTS` でメッセージを指定した場合はそれを尊重する
- コミットメッセージは HEREDOC で渡してフォーマットを保持する
- pre-commit フック失敗時は `--amend` せず新規コミットを作成する
