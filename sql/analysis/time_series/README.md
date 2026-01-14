# 時系列パターン分析

## 📋 概要

各台の過去データを時系列として分析し、「高設定投入の周期性」や「底打ち→反転パターン」を検出する手法です。

**ステータス**: 📅 計画中（Phase 2）

---

## 📂 ファイル構成（計画）

```
time_series/
├── README.md                           # このファイル
├── time_series_output.sql              # 狙い台一覧出力クエリ（予定）
├── time_series_evaluation.sql          # 評価クエリ（予定）
├── scripts/
│   └── analyze_results.py              # 結果分析スクリプト（予定）
└── results/
    └── YYYY-MM-DD/                     # 評価実行日ごとの結果
```

---

## 🎯 分析要素

### 1. 曜日別パフォーマンス

各台の曜日ごとの勝率・機械割を分析し、曜日傾向を検出。

```sql
-- 例: 各台の曜日別勝率
SELECT 
  machine_number,
  EXTRACT(DAYOFWEEK FROM target_date) AS weekday,
  AVG(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) AS win_rate,
  AVG(d1_payout_rate) AS avg_payout_rate
FROM daily_data
GROUP BY machine_number, weekday
```

**活用例**:
- 「この台は金曜に強い（勝率70%）」
- 「月曜は全体的に設定が低い傾向」

### 2. 周期性検出

7日・14日・30日周期での高設定パターンを検出。

```sql
-- 例: 7日周期での勝率分析
SELECT
  machine_number,
  MOD(DATE_DIFF(target_date, reference_date, DAY), 7) AS cycle_day,
  AVG(CASE WHEN d1_diff > 0 THEN 1 ELSE 0 END) AS win_rate
FROM daily_data
GROUP BY machine_number, cycle_day
```

**活用例**:
- 「この台は7日周期で高設定が入る傾向」
- 「14日周期でローテーションしている可能性」

### 3. 移動平均トレンド

短期移動平均と長期移動平均を比較し、トレンド転換を検出。

```sql
-- 例: ゴールデンクロス検出
SELECT
  machine_number,
  target_date,
  AVG(d1_payout_rate) OVER (PARTITION BY machine_number ORDER BY target_date ROWS 2 PRECEDING) AS ma3,
  AVG(d1_payout_rate) OVER (PARTITION BY machine_number ORDER BY target_date ROWS 6 PRECEDING) AS ma7,
  CASE 
    WHEN ma3 > ma7 AND LAG(ma3) OVER (...) <= LAG(ma7) OVER (...) 
    THEN 'ゴールデンクロス'
    ELSE NULL 
  END AS signal
FROM daily_data
```

**活用例**:
- 「短期MAが長期MAを上抜け（上昇トレンド転換）」
- 「下降トレンドから反転の兆し」

### 4. 連続不調後リバウンド

N日連続負けの後の勝率を分析し、「調整日」パターンを検出。

```sql
-- 例: 3連敗後の翌日勝率
WITH streak_data AS (
  SELECT
    machine_number,
    target_date,
    d1_diff,
    -- 直近3日連続マイナスかどうか
    CASE 
      WHEN LAG(d1_diff, 1) OVER (...) < 0 
       AND LAG(d1_diff, 2) OVER (...) < 0 
       AND LAG(d1_diff, 3) OVER (...) < 0 
      THEN TRUE 
      ELSE FALSE 
    END AS prev_3d_all_lose
  FROM daily_data
)
SELECT
  machine_number,
  COUNT(CASE WHEN prev_3d_all_lose AND d1_diff > 0 THEN 1 END) AS rebound_wins,
  COUNT(CASE WHEN prev_3d_all_lose THEN 1 END) AS total_rebounds,
  SAFE_DIVIDE(rebound_wins, total_rebounds) AS rebound_rate
FROM streak_data
GROUP BY machine_number
```

**活用例**:
- 「3連敗後の翌日は勝率60%（リバウンド傾向あり）」
- 「5連敗後は設定変更の可能性が高い」

### 5. ボラティリティ分析

成績の振れ幅を分析し、設定変更頻度を推定。

```sql
-- 例: 機械割のボラティリティ（標準偏差）
SELECT
  machine_number,
  STDDEV(d1_payout_rate) AS volatility,
  CASE 
    WHEN STDDEV(d1_payout_rate) > 0.1 THEN '高ボラ（設定変更頻繁）'
    WHEN STDDEV(d1_payout_rate) > 0.05 THEN '中ボラ'
    ELSE '低ボラ（設定固定気味）'
  END AS volatility_category
FROM daily_data
GROUP BY machine_number
```

**活用例**:
- 「高ボラ台 → 毎日設定が変わる可能性」
- 「低ボラ台 → 設定が固定されている可能性」

---

## 📊 スコア計算（案）

```
時系列スコア = 曜日スコア × α 
             + トレンドスコア × β 
             + リバウンドスコア × γ 
             + ボラティリティスコア × δ
```

| 要素 | 重み案 | 説明 |
|------|--------|------|
| 曜日スコア | 0.3 | 対象曜日のパフォーマンスランキング |
| トレンドスコア | 0.3 | ゴールデンクロス発生で加点 |
| リバウンドスコア | 0.25 | 連続不調後のリバウンド率 |
| ボラティリティスコア | 0.15 | 高ボラ台で加点（設定変更の機会） |

---

## 🚀 開発タスク

| タスク | 説明 | ステータス |
|--------|------|-----------|
| 要件定義・設計 | 分析する時系列パターンの定義 | 📅 計画中 |
| データ準備 | 必要なデータマートカラムの追加検討 | 📅 計画中 |
| 曜日別分析クエリ | 曜日別パフォーマンス分析 | 📅 計画中 |
| 周期性分析クエリ | 7/14/30日周期パターン検出 | 📅 計画中 |
| トレンド分析クエリ | 移動平均・ゴールデンクロス | 📅 計画中 |
| リバウンド分析クエリ | 連続不調後の勝率分析 | 📅 計画中 |
| 評価クエリ作成 | 過去データでの検証 | 📅 計画中 |
| ドキュメント作成 | README・使い方ガイド | 📅 計画中 |

---

## 💡 期待される効果

### 既存手法（戦略マッチング）との補完

| 観点 | 戦略マッチング | 時系列パターン |
|------|---------------|---------------|
| 時間軸 | 考慮なし | ◎ 曜日・周期を考慮 |
| トレンド | 過去N日の平均 | ◎ 推移・転換を検出 |
| リバウンド | 考慮なし | ◎ 連続不調後を狙う |
| ボラティリティ | 考慮なし | ◎ 設定変更頻度を推定 |

### 想定される改善

- **曜日傾向の活用**: 特定曜日に強い台を優先的に狙う
- **トレンド転換の検出**: 上昇トレンドに転じた台を早期に発見
- **調整日の予測**: 連続不調後のリバウンドを狙う

---

## ⚠️ 注意事項・リスク

- **データ量の要件**: 信頼性のある分析には最低30日以上のデータが必要
- **周期性の偽検出**: 偶然の一致を周期と誤認するリスク
- **過学習**: 過去パターンが将来も続くとは限らない

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
