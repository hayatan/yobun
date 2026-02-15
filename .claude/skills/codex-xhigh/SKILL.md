---
name: codex-xhigh
description: "Use proactively whenever calling codex MCP tools (mcp__codex__codex, mcp__codex__codex-reply). Enforces gpt-5.3-codex model with xhigh reasoning_effort. Triggers on: codex, ask codex, codex review, codex check, codex investigate, codex research."
---

# Codex MCP 呼び出し設定（gpt-5.3-codex / xhigh）

## ルール（例外なし）

**codex MCP のツール（`mcp__codex__codex` および `mcp__codex__codex-reply`）を呼び出す際は、必ず以下の設定を適用する。**

### 必須パラメータ

| パラメータ | 値 | 説明 |
|-----------|-----|------|
| `model` | `gpt-5.3-codex` | 使用モデル |
| `config.reasoning_effort` | `xhigh` | 推論の深さを最大に設定 |
| `cwd` | 作業ディレクトリ | Codex がファイルを直接参照するために必要 |

### 適用例

#### 新規会話（`mcp__codex__codex`）

```json
{
  "prompt": "...",
  "model": "gpt-5.3-codex",
  "cwd": "/home/hayatan/nekonote",
  "config": {
    "reasoning_effort": "xhigh"
  }
}
```

#### 会話継続（`mcp__codex__codex-reply`）

`codex-reply` にはモデル指定パラメータがないため、最初の `codex` 呼び出し時に正しいモデルと設定を適用すること。

### Codex のファイル参照とコンテキスト

Codex は `cwd` で指定されたディレクトリ内のファイルを `ls`, `cat`, `find` 等のコマンドで自力で読み取れる。
そのため：

- **コード全文をプロンプトに貼り付ける必要はない**
- ファイルパスを指示するだけでよい（例: 「`scripts/launch.sh` を見て問題点を指摘して」）
- 差分を渡す場合も「`git diff` を実行して確認して」で十分

ただし **Codex はこちらの会話コンテキストを共有していない**。
プロンプトには背景・経緯を含め、必要に応じて `.tasks/plans/` のパスも渡すこと。
詳細は dev-flow スキルの「プロンプトの書き方」セクションを参照。

### 対象となる場面

- dev-flow における調査・レビュー（詳細は dev-flow スキル参照）
- 実装中の突発的な疑問やアクシデント（インタラクティブに何往復でも可）
- 設計判断に迷ったとき
- その他、codex MCP を利用するすべての場面

### 注意事項

- `model` や `config.reasoning_effort` を省略してはならない。
- 別のモデル（例: `o4-mini`）や低い effort（例: `high`, `medium`）に変更してはならない。
- ユーザーが明示的に別のモデルや effort を指定した場合のみ、このルールを上書きできる。
