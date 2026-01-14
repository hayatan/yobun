# 台番相関分析

## 📋 概要

台同士の成績相関を分析し、「同時に高設定が入りやすいグループ（シマ）」や「翌日に連動するパターン」を検出する手法です。設定師のローテーションパターンを捉えることを目的とします。

**ステータス**: 📅 計画中（Phase 3）

---

## 📂 ファイル構成（計画）

```
correlation/
├── README.md                           # このファイル
├── correlation_output.sql              # 狙い台一覧出力クエリ（予定）
├── correlation_evaluation.sql          # 評価クエリ（予定）
├── scripts/
│   └── analyze_results.py              # 結果分析スクリプト（予定）
└── results/
    └── YYYY-MM-DD/                     # 評価実行日ごとの結果
```

---

## 🎯 分析要素

### 1. 同日相関分析

同じ日に好調になりやすい台のペアを検出。

```sql
-- 例: 台ペアの同日相関係数
WITH daily_performance AS (
  SELECT
    target_date,
    machine_number,
    d1_payout_rate,
    d1_diff
  FROM `yobun-450512.datamart.machine_stats`
  WHERE hole = 'アイランド秋葉原店' AND machine = 'L+ToLOVEるダークネス'
)
SELECT
  a.machine_number AS machine_a,
  b.machine_number AS machine_b,
  CORR(a.d1_payout_rate, b.d1_payout_rate) AS correlation,
  -- 両方プラスの確率
  COUNT(CASE WHEN a.d1_diff > 0 AND b.d1_diff > 0 THEN 1 END) / COUNT(*) AS both_win_rate
FROM daily_performance a
INNER JOIN daily_performance b 
  ON a.target_date = b.target_date 
  AND a.machine_number < b.machine_number  -- 重複排除
GROUP BY machine_a, machine_b
HAVING COUNT(*) >= 30  -- 最低30日以上のデータ
ORDER BY correlation DESC
```

**活用例**:
- 「台1265と台1266は相関0.7 → シマ上げの可能性」
- 「両方同時に勝つ確率が40% → グループで狙う価値あり」

### 2. 翌日相関分析（ローテーション検出）

台Aが好調の翌日に台Bが好調になる確率を分析。

```sql
-- 例: 翌日連動パターン
WITH daily_with_next AS (
  SELECT
    a.target_date,
    a.machine_number AS machine_a,
    a.d1_diff AS diff_a,
    b.machine_number AS machine_b,
    b.d1_diff AS diff_b_next
  FROM daily_performance a
  INNER JOIN daily_performance b 
    ON DATE_ADD(a.target_date, INTERVAL 1 DAY) = b.target_date
)
SELECT
  machine_a,
  machine_b,
  -- 台Aが勝った翌日に台Bが勝つ確率
  COUNT(CASE WHEN diff_a > 0 AND diff_b_next > 0 THEN 1 END) /
  NULLIF(COUNT(CASE WHEN diff_a > 0 THEN 1 END), 0) AS next_day_win_rate,
  -- 逆パターン（台Aが負けた翌日に台Bが勝つ確率）
  COUNT(CASE WHEN diff_a < 0 AND diff_b_next > 0 THEN 1 END) /
  NULLIF(COUNT(CASE WHEN diff_a < 0 THEN 1 END), 0) AS rotation_rate
FROM daily_with_next
GROUP BY machine_a, machine_b
HAVING COUNT(*) >= 30
ORDER BY rotation_rate DESC
```

**活用例**:
- 「台1265が好調の翌日は台1267が好調になりやすい（ローテーション）」
- 「台1265が不調の翌日は台1266に設定が入る傾向」

### 3. グループクラスタリング

相関の高い台をグループ化し、設定投入パターンを推定。

```sql
-- 例: 相関行列からグループを特定
WITH correlation_matrix AS (
  -- 上記の同日相関分析結果
  ...
),
high_correlation_pairs AS (
  SELECT * FROM correlation_matrix WHERE correlation > 0.5
)
-- グラフアルゴリズムでクラスタリング
-- （BigQuery MLのk-meansや、Pythonでの後処理を検討）
```

**活用例**:
- 「台1265, 1266, 1267はグループA（同時に上がる傾向）」
- 「グループAが好調の翌日はグループBに注目」

### 4. 隣接台分析

物理的に隣の台との連動を分析。

```sql
-- 例: 隣接台の同日パフォーマンス相関
SELECT
  a.machine_number,
  AVG(CASE WHEN a.d1_diff > 0 AND b.d1_diff > 0 THEN 1 ELSE 0 END) AS neighbor_same_win_rate,
  AVG(CASE WHEN a.d1_diff > 0 AND b.d1_diff < 0 THEN 1 ELSE 0 END) AS neighbor_opposite_rate
FROM daily_performance a
INNER JOIN daily_performance b 
  ON a.target_date = b.target_date 
  AND ABS(a.machine_number - b.machine_number) = 1  -- 隣接台
GROUP BY a.machine_number
```

**活用例**:
- 「この台は隣と同時に好調になりやすい → シマ上げ傾向」
- 「隣接台との勝敗が逆転しやすい → 交互パターン」

### 5. 末尾番号グループ分析

末尾が同じ台の連動を分析。

```sql
-- 例: 末尾番号グループの同日パフォーマンス
SELECT
  MOD(machine_number, 10) AS last_digit,
  target_date,
  AVG(d1_payout_rate) AS avg_payout_rate,
  AVG(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) AS group_win_rate
FROM daily_performance
GROUP BY last_digit, target_date
```

**活用例**:
- 「末尾5の台が同時に上がる日がある」
- 「末尾狙いの精度向上に活用」

---

## 📊 スコア計算（案）

```
相関スコア = グループ内好調度 × α 
           + 翌日ローテーションスコア × β 
           + 隣接台スコア × γ
```

| 要素 | 重み案 | 説明 |
|------|--------|------|
| グループ内好調度 | 0.4 | 高相関グループの本日好調率 |
| ローテーションスコア | 0.4 | 前日好調台からの連動予測 |
| 隣接台スコア | 0.2 | 隣接台のパフォーマンス |

---

## 🚀 開発タスク

| タスク | 説明 | ステータス |
|--------|------|-----------|
| 要件定義・設計 | 相関分析の手法選定 | 📅 計画中 |
| 同日相関分析 | 同じ日に好調になりやすい台ペア | 📅 計画中 |
| 翌日相関分析 | 翌日に連動するパターン | 📅 計画中 |
| グループクラスタリング | 相関の高い台のグループ化 | 📅 計画中 |
| 隣接台・末尾分析 | 物理的位置に基づく分析 | 📅 計画中 |
| 評価クエリ作成 | 過去データでの検証 | 📅 計画中 |
| ドキュメント作成 | README・使い方ガイド | 📅 計画中 |

---

## 💡 期待される効果

### 既存手法（戦略マッチング）との補完

| 観点 | 戦略マッチング | 相関分析 |
|------|---------------|----------|
| 台同士の関係 | 考慮なし | ◎ シマ・グループを考慮 |
| ローテーション | 考慮なし | ◎ 翌日連動を検出 |
| 隣接効果 | 考慮なし | ◎ 物理的位置を考慮 |

### 想定される改善

- **シマ上げの検出**: 同時に高設定が入るグループを特定
- **ローテーション予測**: 翌日に設定が入りやすい台を予測
- **グループ単位での判断**: 単独台だけでなく周囲の状況も考慮

---

## ⚠️ 注意事項・リスク

- **データ量の要件**: 相関分析には最低60日以上のデータが推奨
- **相関 ≠ 因果**: 相関が高くても因果関係があるとは限らない
- **計算量**: 台ペアの全組み合わせは O(n²) で増加
- **過学習**: 過去の相関パターンが将来も続くとは限らない

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
