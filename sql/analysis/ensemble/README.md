# アンサンブル統合

## 📋 概要

Phase 1〜4の各分析手法（戦略マッチング、時系列パターン、相関分析、機械学習）を統合し、より堅牢な予測を行う手法です。複数の視点からの「合意」がある台を優先的に狙います。

**ステータス**: 📅 計画中（Phase 5）

**前提条件**: Phase 1〜4が完了していること

---

## 📂 ファイル構成（計画）

```
ensemble/
├── README.md                           # このファイル
├── ensemble_output.sql                 # 統合狙い台一覧出力クエリ（予定）
├── ensemble_evaluation.sql             # 評価クエリ（予定）
├── weight_optimization.sql             # 重み最適化クエリ（予定）
├── scripts/
│   └── optimize_weights.py             # 重み最適化スクリプト（予定）
└── results/
    └── YYYY-MM-DD/                     # 評価実行日ごとの結果
```

---

## 🎯 統合アプローチ

### 基本構造

```
最終スコア = α × 戦略マッチングスコア（Phase 1）
           + β × 時系列パターンスコア（Phase 2）
           + γ × 相関分析スコア（Phase 3）
           + δ × ML予測スコア（Phase 4）

制約: α + β + γ + δ = 1
```

### 統合方法の選択肢

#### 方法1: 単純加重平均

各手法のスコアを正規化し、重み付け平均を取る。

```sql
SELECT
  machine_number,
  -- 各手法のスコアを0-1に正規化
  PERCENT_RANK() OVER (ORDER BY strategy_score) AS norm_strategy,
  PERCENT_RANK() OVER (ORDER BY time_series_score) AS norm_time_series,
  PERCENT_RANK() OVER (ORDER BY correlation_score) AS norm_correlation,
  PERCENT_RANK() OVER (ORDER BY ml_score) AS norm_ml,
  -- 重み付け平均
  0.3 * norm_strategy 
  + 0.25 * norm_time_series 
  + 0.25 * norm_correlation 
  + 0.2 * norm_ml AS ensemble_score
FROM all_scores
```

#### 方法2: ランク統合

各手法のランキングを統合し、総合ランキングを算出。

```sql
SELECT
  machine_number,
  -- 各手法のランク
  ROW_NUMBER() OVER (ORDER BY strategy_score DESC) AS strategy_rank,
  ROW_NUMBER() OVER (ORDER BY time_series_score DESC) AS time_series_rank,
  ROW_NUMBER() OVER (ORDER BY correlation_score DESC) AS correlation_rank,
  ROW_NUMBER() OVER (ORDER BY ml_score DESC) AS ml_rank,
  -- ランクの平均（小さいほど良い）
  (strategy_rank + time_series_rank + correlation_rank + ml_rank) / 4.0 AS avg_rank
FROM all_scores
ORDER BY avg_rank ASC
```

#### 方法3: 投票方式

各手法でTOP5に入った回数をカウント。

```sql
SELECT
  machine_number,
  -- 各手法でTOP5に入っているかどうか
  CASE WHEN strategy_rank <= 5 THEN 1 ELSE 0 END AS strategy_vote,
  CASE WHEN time_series_rank <= 5 THEN 1 ELSE 0 END AS time_series_vote,
  CASE WHEN correlation_rank <= 5 THEN 1 ELSE 0 END AS correlation_vote,
  CASE WHEN ml_rank <= 5 THEN 1 ELSE 0 END AS ml_vote,
  -- 投票数の合計
  strategy_vote + time_series_vote + correlation_vote + ml_vote AS total_votes
FROM ranked_scores
ORDER BY total_votes DESC, ensemble_score DESC
```

#### 方法4: 条件付き統合

各手法の信頼度に応じて動的に重みを調整。

```sql
SELECT
  machine_number,
  -- 各手法の信頼度（過去の精度に基づく）
  CASE WHEN strategy_method_accuracy > 0.55 THEN 0.35 ELSE 0.20 END AS alpha,
  CASE WHEN time_series_accuracy > 0.55 THEN 0.25 ELSE 0.15 END AS beta,
  CASE WHEN correlation_accuracy > 0.55 THEN 0.25 ELSE 0.15 END AS gamma,
  1 - alpha - beta - gamma AS delta,
  -- 動的重み付け平均
  alpha * norm_strategy 
  + beta * norm_time_series 
  + gamma * norm_correlation 
  + delta * norm_ml AS dynamic_ensemble_score
FROM all_scores_with_accuracy
```

---

## 📊 重み最適化

### 目的関数

過去データで最も高い機械割を達成する重み（α, β, γ, δ）を探索。

```
maximize: 平均機械割（TOP3予測の実績）
subject to: α + β + γ + δ = 1, 0 ≤ α, β, γ, δ ≤ 1
```

### グリッドサーチ

```sql
-- 重みの候補を列挙
WITH weight_candidates AS (
  SELECT 
    alpha, beta, gamma, 1 - alpha - beta - gamma AS delta
  FROM UNNEST([0.1, 0.2, 0.3, 0.4, 0.5]) AS alpha,
       UNNEST([0.1, 0.2, 0.3, 0.4, 0.5]) AS beta,
       UNNEST([0.1, 0.2, 0.3, 0.4, 0.5]) AS gamma
  WHERE alpha + beta + gamma <= 1
),
-- 各重みでの評価
evaluation AS (
  SELECT
    w.alpha, w.beta, w.gamma, w.delta,
    AVG(actual_payout_rate) AS avg_payout_rate
  FROM weight_candidates w
  CROSS JOIN all_scores s
  WHERE (w.alpha * s.norm_strategy + w.beta * s.norm_time_series + ...) >= 0.95  -- TOP5%
  GROUP BY w.alpha, w.beta, w.gamma, w.delta
)
SELECT * FROM evaluation ORDER BY avg_payout_rate DESC LIMIT 10;
```

### ベイズ最適化（Python）

```python
# scripts/optimize_weights.py
from bayes_opt import BayesianOptimization
import pandas as pd

def evaluate_weights(alpha, beta, gamma):
    delta = 1 - alpha - beta - gamma
    if delta < 0:
        return -1  # 無効な組み合わせ
    
    # 重み付けスコアを計算
    scores['ensemble'] = (
        alpha * scores['norm_strategy'] +
        beta * scores['norm_time_series'] +
        gamma * scores['norm_correlation'] +
        delta * scores['norm_ml']
    )
    
    # TOP3の平均機械割を計算
    top3 = scores.nlargest(3, 'ensemble')
    return top3['actual_payout_rate'].mean()

# ベイズ最適化
optimizer = BayesianOptimization(
    f=evaluate_weights,
    pbounds={'alpha': (0.1, 0.5), 'beta': (0.1, 0.4), 'gamma': (0.1, 0.4)},
    random_state=42
)
optimizer.maximize(init_points=10, n_iter=50)

print(f"最適な重み: {optimizer.max}")
```

---

## 🔧 出力形式

### 統合スコア出力

```sql
SELECT
  machine_number,
  -- 各手法のスコア
  strategy_score,
  time_series_score,
  correlation_score,
  ml_score,
  -- 統合スコア
  ensemble_score,
  -- ランキング
  ROW_NUMBER() OVER (ORDER BY ensemble_score DESC) AS ensemble_rank,
  -- 合意度（複数手法でTOP10に入っている数）
  strategy_top10 + time_series_top10 + correlation_top10 + ml_top10 AS consensus_count,
  -- 優先度ランク
  CASE
    WHEN ensemble_rank <= 1 THEN 5
    WHEN ensemble_rank <= 3 THEN 4
    WHEN ensemble_rank <= 5 THEN 3
    WHEN consensus_count >= 3 THEN 3  -- 3手法以上で合意
    WHEN ensemble_rank <= 10 THEN 2
    ELSE 1
  END AS priority_rank
FROM ensemble_scores
ORDER BY ensemble_score DESC
```

---

## 🚀 開発タスク

| タスク | 説明 | ステータス |
|--------|------|-----------|
| 統合設計 | 各手法の重み付け方法検討 | 📅 計画中 |
| 統合クエリ作成 | 各手法のスコアを統合 | 📅 計画中 |
| 重み最適化 | 評価結果に基づく重み調整 | 📅 計画中 |
| 評価・検証 | 過去データでの検証 | 📅 計画中 |
| ドキュメント作成 | README・使い方ガイド | 📅 計画中 |

---

## 💡 期待される効果

### アンサンブルのメリット

| 観点 | 単一手法 | アンサンブル |
|------|----------|-------------|
| 堅牢性 | 手法の弱点に弱い | ◎ 弱点を補完 |
| 合意の信頼度 | - | ◎ 複数視点で確認 |
| 過学習リスク | 高い | 低い（多様性で軽減） |
| 安定性 | 手法により変動 | ◎ 安定 |

### 想定される改善

- **信頼度の向上**: 複数手法で一致する台は高確率で高設定
- **リスク軽減**: 単一手法の失敗を他手法でカバー
- **新パターンへの対応**: 1つの手法が失敗しても他がカバー

---

## ⚠️ 注意事項・リスク

- **前提条件**: Phase 1〜4の完成が必要
- **計算量**: 4手法分のスコア計算が必要
- **重みの過学習**: 過去データに最適化しすぎると将来に弱い
- **運用の複雑さ**: 4手法すべての更新・保守が必要

---

## 📊 評価指標

| 指標 | 説明 | 目標値 |
|------|------|--------|
| **勝率** | TOP3予測の勝率 | 60%以上 |
| **機械割** | TOP3予測の機械割 | 105%以上 |
| **単一手法との差** | 最良単一手法との機械割差 | +1%以上 |
| **安定性** | 週間勝率の標準偏差 | 低いほど良い |

---

## 🔄 変更履歴

| 日付 | 変更内容 |
|------|----------|
| 2026-01-14 | README初版作成 |

---

## 📚 関連ドキュメント

- [全体README](../README.md)
- [開発ロードマップ](../ROADMAP.md)
- [戦略マッチング手法](../strategy_matching/README.md)
- [時系列パターン分析](../time_series/README.md)
- [台番相関分析](../correlation/README.md)
- [機械学習予測](../machine_learning/README.md)
