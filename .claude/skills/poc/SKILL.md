---
name: poc
description: "Use proactively when proof-of-concept work is needed to resolve technical uncertainty before implementation. Guides POC planning, execution, result recording, and archival workflow. Triggers on: POC, proof of concept, spike, technical uncertainty, feasibility, validate approach, compare approaches, prototype approach."
---

# POC（Proof of Concept）管理フロー

## POC の実施手順

### 1. POC ノード作成
`.tasks/plans/poc-<name>.md` を `.tasks/templates/poc.md` をベースに作成する。

- 命名規則: `poc-<kebab-case-name>.md`
- Hypothesis（仮説）と Background（背景）を先に記入する
- Parent で通常のタスクノードとリンク可能

### 2. 実験環境の準備
`.playground/poc-<name>/` にサブディレクトリを作成する。

- playground スキルの環境を利用（git 管理外のサンドボックス）
- 実験コードはすべてこのディレクトリ内に閉じ込める

### 3. セッション安全性を確保して実行
以下のルールに従って POC を実行する（詳細は後述）。

### 4. 結果を POC ノードに記録
- Result セクションに定量的・定性的結果を記載
- Verdict を設定: `untested` / `validated` / `invalidated` / `partial`
- Key Findings に得られた知見を記載

### 5. 判断と後処理
Decision セクションで後処理を選択する:

| 判断 | 後処理 |
|------|--------|
| 本実装に採用 | `.tasks/plans/` にタスクノード作成、Phase 3（計画）へ |
| 見送り | `docs/proposals/` にアーカイブ（転記手順参照） |
| 追加検証 | 新しい POC ノード作成、Phase 2.5 を繰り返す |

---

## セッション安全性のルール

1. **POC コードは `.playground/poc-<name>/` 内に閉じ込める** — 親ディレクトリや本番コードを書き換えない
2. **タイムアウトを付与** — `timeout` コマンドまたは Bash ツールの timeout パラメータを使う
3. **大規模・高リスクの POC はエージェントに委譲** — メインセッションのクラッシュ防止のため Task ツールでサブエージェントに実行させる
4. **実行前に POC ノードの Method を記入** — セッション断後の復帰に備える
5. **長時間処理はバックグラウンド + ログ出力** — Bash の `run_in_background` を活用する
6. **後片付け** — POC 完了後、バックグラウンドプロセスが残っていないか確認する。不要になった `.playground/poc-<name>/` は POC ノードが `done` になった後に削除してよい

---

## POC テンプレートのフィールド説明

| フィールド | 説明 |
|-----------|------|
| Status | `not_started` / `in_progress` / `blocked` / `done`（通常ノードと同じ） |
| Owner | 担当エージェント名 |
| Updated | 最終更新日 |
| Parent | 親ノードのパス（独立 POC なら `none`） |
| Hypothesis | 検証したい仮説（「〜すれば〜できるはず」の形式が望ましい） |
| Background | POC を実施する背景と動機 |
| Method | 検証手順のチェックリスト |
| Playground | 実験ディレクトリのパスと使用コマンド |
| Result / Verdict | 検証結果と判定 |
| Key Findings | POC から得られた知見（成功・失敗問わず） |
| Decision | 後処理の選択 |
| Blockers | ブロッカー（なければ「なし」） |
| NextAction | 次にやる1手（セッション復帰用） |

### 記入例（Hypothesis）
```
- TypeScript の Dynamic Import を使えば、エージェント定義を実行時に遅延ロードできるはず
- これにより起動時間が 50% 以上短縮されることを検証する
```

---

## 提案アーカイブへの転記手順

POC の結果は良かったが CONCEPT.md を踏まえて見送る場合:

1. `docs/proposals/NNNN-<kebab-case-title>.md` を作成（4桁連番、採番ルールは `docs/proposals/AGENTS.md` 参照）
2. `docs/proposals/AGENTS.md` のテンプレート構成に従ってセクションを記入:
   - Summary — POC の概要と結論
   - Motivation — なぜ検討したか
   - Proposal Detail — 具体的な提案内容
   - POC Results — Verdict と主要な結果データ
   - Why Deferred — 見送り理由（CONCEPT.md のどの方針と合わないか等）
   - Conditions for Reconsideration — どういう条件が変われば再検討するか
   - Key Takeaways — 他にも活用できる知見
3. POC ノードの Decision で「見送り → docs/proposals/ にアーカイブ」にチェック
4. POC ノードを `Status: done` にする
