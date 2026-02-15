# .tasks — AI エージェント専用の作業記憶域

> **警告: `.tasks/` は nekonote の機能とは一切無関係である。**
> nekonote は自律開発ツールキットだが、`.tasks/` はその nekonote を「開発するため」にAIエージェントが使う作業メモにすぎない。
> `.tasks/` の構造・内容・テンプレートを nekonote の機能として組み込んではならない。逆に nekonote の機能設計を `.tasks/` に反映してもならない。両者は完全に独立している。

## 目的

AIエージェントが自律的に作業するための記憶域。人間が直接読むことは想定しない。
「どんな計画があるか」「どこまで終わったか」「何がブロックしているか」をエージェント間で共有する。

## 構成

```
.tasks/
├── AGENTS.md           # このファイル（利用ルール）
├── templates/
│   ├── node.md         # 統一テンプレート（root も子も同じ形式）
│   └── poc.md          # POC 専用テンプレート（仮説検証用）
└── plans/              # 実際の計画ファイル
    ├── root.md         # ルートノード（Parent: none）
    └── *.md            # 子ノード
```

## テンプレート

`templates/node.md` を使う。root も子ノードも同じ形式。

- **root ノード**: `Parent: none` にする
- **子ノード**: `Parent: plans/root.md` のように親パスを書く

**POC 用には `templates/poc.md` を使う。**

- 命名規則: `poc-<kebab-case-name>.md`（plans/ 内に配置）
- Verdict: `untested` / `validated` / `invalidated` / `partial`
- POC ノードも Parent で通常ノードの Children にできる
- 対応する実験コードは `.playground/poc-<name>/` に配置する
- POC テンプレートでは通常の Goal → Hypothesis、Done条件 → Verdict + Decision が対応する

**POC テンプレートの必須フィールド:**

| フィールド | 説明 |
|-----------|------|
| Status | `not_started` / `in_progress` / `blocked` / `done` |
| Owner | 担当エージェント名。未割当なら `unassigned` |
| Updated | 最終更新日（YYYY-MM-DD） |
| Parent | 親ノードのパス。独立 POC は `none` |
| Hypothesis | 検証したい仮説（通常ノードの Goal に相当） |
| Verdict | `untested` / `validated` / `invalidated` / `partial` |
| Decision | 後処理の選択（通常ノードの Done条件に相当） |
| NextAction | 次にやる1手（復帰時に即再開できるように） |

### 必須フィールド

| フィールド | 説明 |
|-----------|------|
| Status | `not_started` / `in_progress` / `blocked` / `done` |
| Owner | 担当エージェント名。未割当なら `unassigned` |
| Updated | 最終更新日（YYYY-MM-DD） |
| Parent | 親ノードのパス。ルートは `none` |
| Goal | 何を達成するか（1〜3行） |
| Done条件 | 完了判定のチェックリスト |
| NextAction | 次にやる1手（復帰時に即再開できるように） |

### Items と Children の使い分け

- **Items**: 1セッションで終わる作業。チェックボックスで管理
- **Children**: 分割・委譲する作業。別ファイルに切り出す

## 基本ルール

1. **必要なノードだけ読む** — root の Children で全体を把握し、該当ノードだけ開く
2. **自分の担当だけ更新する** — 1ノード1ライター。Owner でないノードを直接編集しない
3. **更新時は Status, Updated, NextAction を必ず更新する**
4. **完了時は Done条件のチェックを全て埋めてから `Status: done` にする**

## いつ使うか

- 複数ファイルにまたがる変更や、複数の独立した作業が発生するとき
- エージェントを spawn して並列に進めるとき
- セッションをまたいで作業状態を引き継ぐ必要があるとき

## エージェント spawn 時

- 担当ノードのパスを伝える
- エージェントは自分のノードの Status, Updated, NextAction を更新する
- 完了したら Done条件を全てチェックし、`Status: done` にして親に報告する

## セッション復帰手順

1. `plans/root.md` を読む（未作成なら `templates/node.md` をコピーして `Parent: none` で作成する）
2. Children から `in_progress` または `blocked` のノードだけ開く
3. 自分の Owner のノードを見つける
4. NextAction から再開する
