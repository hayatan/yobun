# 機械学習予測

## 📋 概要

過去データで機械学習モデルを訓練し、各台の翌日の「勝率」または「機械割」を直接予測する手法です。BigQuery MLまたはPython（LightGBM等）を使用します。

**ステータス**: 📅 計画中（Phase 4）

---

## 📂 ファイル構成（計画）

```
machine_learning/
├── README.md                           # このファイル
├── feature_engineering.sql             # 特徴量生成クエリ（予定）
├── bqml_training.sql                   # BigQuery MLモデル訓練（予定）
├── bqml_prediction.sql                 # BigQuery ML予測クエリ（予定）
├── scripts/
│   ├── train_model.py                  # Pythonモデル訓練スクリプト（予定）
│   ├── predict.py                      # Python予測スクリプト（予定）
│   └── evaluate.py                     # 評価スクリプト（予定）
├── models/
│   └── model_YYYYMMDD.pkl              # 訓練済みモデル（予定）
└── results/
    └── YYYY-MM-DD/                     # 評価実行日ごとの結果
```

---

## 🎯 アプローチ

### Option A: BigQuery ML（SQLのみで完結）

BigQueryの機械学習機能を使用し、SQLだけでモデル訓練・予測を行う。

**メリット**:
- SQLのみで完結、追加インフラ不要
- BigQuery Connectorから直接使用可能
- スケジュールクエリで自動化可能

**デメリット**:
- モデルの種類が限定的
- ハイパーパラメータ調整が難しい

### Option B: Python（LightGBM等）

Pythonスクリプトで高度なモデルを訓練し、予測結果をBigQueryに保存。

**メリット**:
- モデルの選択肢が豊富
- 詳細なチューニングが可能
- 特徴量重要度の可視化

**デメリット**:
- 追加のインフラ（Cloud Functionsなど）が必要
- 運用が複雑

---

## 📊 特徴量設計

### 基本統計

| 特徴量 | 説明 | データソース |
|--------|------|-------------|
| `prev_d3_win_rate` | 過去3日間の勝率 | datamart.machine_stats |
| `prev_d5_win_rate` | 過去5日間の勝率 | datamart.machine_stats |
| `prev_d7_win_rate` | 過去7日間の勝率 | datamart.machine_stats |
| `prev_d28_win_rate` | 過去28日間の勝率 | datamart.machine_stats |
| `prev_d28_payout_rate` | 過去28日間の機械割 | datamart.machine_stats |

### 差枚関連

| 特徴量 | 説明 | 計算方法 |
|--------|------|----------|
| `prev_d28_diff` | 過去28日間の差枚合計 | datamart.machine_stats |
| `diff_percentile` | 差枚パーセンタイル | PERCENT_RANK() |
| `diff_rank` | 差枚ランキング | ROW_NUMBER() |

### 時系列

| 特徴量 | 説明 | 計算方法 |
|--------|------|----------|
| `consecutive_wins` | 直近連勝数 | ウィンドウ関数 |
| `consecutive_losses` | 直近連敗数 | ウィンドウ関数 |
| `ma3_ma7_diff` | 3日MA - 7日MA | 移動平均の差 |
| `volatility` | 機械割の標準偏差 | STDDEV() |

### 曜日・日付

| 特徴量 | 説明 | 計算方法 |
|--------|------|----------|
| `weekday` | 曜日（0-6） | EXTRACT(DAYOFWEEK) |
| `is_weekend` | 週末フラグ | weekday IN (1, 7) |
| `day_of_month` | 月内日（1-31） | EXTRACT(DAY) |
| `is_month_end` | 月末フラグ | target_date = LAST_DAY() |

### 特日

| 特徴量 | 説明 | 計算方法 |
|--------|------|----------|
| `is_special_day` | 特日フラグ | 店舗ごとの定義 |
| `days_since_last_special` | 前回特日からの経過日数 | DATE_DIFF() |
| `days_until_next_special` | 次回特日までの日数 | DATE_DIFF() |

### 台番

| 特徴量 | 説明 | 計算方法 |
|--------|------|----------|
| `machine_last_digit` | 台番末尾1桁 | MOD(machine_number, 10) |
| `machine_last_2digits` | 台番末尾2桁 | MOD(machine_number, 100) |
| `is_corner` | 角台フラグ | 台番が端かどうか |
| `position_in_island` | シマ内の位置 | 台番から計算 |

### 相対位置（Phase 3の結果を活用）

| 特徴量 | 説明 | 計算方法 |
|--------|------|----------|
| `rank_in_island` | シマ内の機械割ランキング | ROW_NUMBER() OVER (PARTITION BY island) |
| `neighbor_avg_payout` | 隣接台の平均機械割 | AVG() with JOIN |
| `group_momentum` | 相関グループの好調度 | 相関分析の結果から計算 |

---

## 🔧 BigQuery ML 実装案

### モデル訓練

```sql
-- 特徴量テーブルの作成
CREATE OR REPLACE TABLE `yobun-450512.ml_features.training_data` AS
SELECT
  target_date,
  machine_number,
  -- 特徴量
  prev_d3_win_rate,
  prev_d7_win_rate,
  prev_d28_win_rate,
  prev_d28_payout_rate,
  diff_percentile,
  consecutive_losses,
  weekday,
  is_special_day,
  machine_last_digit,
  ma3_ma7_diff,
  volatility,
  -- ターゲット（翌日の機械割）
  LEAD(d1_payout_rate, 1) OVER (PARTITION BY machine_number ORDER BY target_date) AS next_day_payout_rate
FROM feature_base_data
WHERE next_day_payout_rate IS NOT NULL;

-- モデル作成（Boosted Tree Regressor）
CREATE OR REPLACE MODEL `yobun-450512.models.slot_prediction_v1`
OPTIONS(
  model_type='BOOSTED_TREE_REGRESSOR',
  input_label_cols=['next_day_payout_rate'],
  data_split_method='AUTO_SPLIT',
  max_iterations=100,
  learn_rate=0.1,
  early_stop=TRUE
) AS
SELECT * EXCEPT(target_date, machine_number)
FROM `yobun-450512.ml_features.training_data`;
```

### 予測

```sql
-- 翌日の機械割を予測
SELECT
  machine_number,
  predicted_next_day_payout_rate,
  PERCENT_RANK() OVER (ORDER BY predicted_next_day_payout_rate DESC) AS prediction_rank
FROM ML.PREDICT(
  MODEL `yobun-450512.models.slot_prediction_v1`,
  (SELECT * FROM `yobun-450512.ml_features.prediction_data`)
)
ORDER BY predicted_next_day_payout_rate DESC;
```

### 特徴量重要度の確認

```sql
-- 特徴量の重要度を確認
SELECT *
FROM ML.FEATURE_IMPORTANCE(MODEL `yobun-450512.models.slot_prediction_v1`)
ORDER BY importance_weight DESC;
```

---

## 🐍 Python 実装案

### 訓練スクリプト

```python
# scripts/train_model.py
import pandas as pd
from google.cloud import bigquery
import lightgbm as lgb
import pickle
from datetime import datetime

# BigQueryからデータ取得
client = bigquery.Client()
query = """
SELECT * FROM `yobun-450512.ml_features.training_data`
WHERE target_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY) AND CURRENT_DATE()
"""
df = client.query(query).to_dataframe()

# 特徴量とターゲットの分離
feature_cols = [
    'prev_d3_win_rate', 'prev_d7_win_rate', 'prev_d28_win_rate',
    'prev_d28_payout_rate', 'diff_percentile', 'consecutive_losses',
    'weekday', 'is_special_day', 'machine_last_digit', 'ma3_ma7_diff', 'volatility'
]
X = df[feature_cols]
y = df['next_day_payout_rate']

# LightGBMモデル訓練
params = {
    'objective': 'regression',
    'metric': 'rmse',
    'n_estimators': 100,
    'learning_rate': 0.1,
    'num_leaves': 31,
    'feature_fraction': 0.8,
    'bagging_fraction': 0.8,
    'bagging_freq': 5,
    'verbose': -1
}
model = lgb.LGBMRegressor(**params)
model.fit(X, y)

# モデル保存
model_path = f'models/model_{datetime.now().strftime("%Y%m%d")}.pkl'
with open(model_path, 'wb') as f:
    pickle.dump(model, f)

# 特徴量重要度の出力
importance = pd.DataFrame({
    'feature': feature_cols,
    'importance': model.feature_importances_
}).sort_values('importance', ascending=False)
print(importance)
```

### 予測スクリプト

```python
# scripts/predict.py
import pandas as pd
from google.cloud import bigquery
import pickle

# モデル読み込み
with open('models/model_latest.pkl', 'rb') as f:
    model = pickle.load(f)

# BigQueryから予測用データ取得
client = bigquery.Client()
query = """
SELECT * FROM `yobun-450512.ml_features.prediction_data`
WHERE target_date = CURRENT_DATE()
"""
df = client.query(query).to_dataframe()

# 予測
predictions = model.predict(df[feature_cols])
df['predicted_payout_rate'] = predictions
df['prediction_rank'] = df['predicted_payout_rate'].rank(ascending=False)

# 結果をBigQueryに保存
df[['machine_number', 'predicted_payout_rate', 'prediction_rank']].to_gbq(
    'ml_predictions.daily_predictions',
    project_id='yobun-450512',
    if_exists='append'
)
```

---

## 🚀 開発タスク

| タスク | 説明 | ステータス |
|--------|------|-----------|
| 要件定義・設計 | 特徴量設計、モデル選定 | 📅 計画中 |
| 特徴量エンジニアリング | 学習用データセット作成 | 📅 計画中 |
| BigQuery MLモデル作成 | SQLベースのモデル訓練 | 📅 計画中 |
| Python実装（オプション） | LightGBM等の高度なモデル | 📅 計画中 |
| 評価・チューニング | ハイパーパラメータ調整 | 📅 計画中 |
| ドキュメント作成 | README・使い方ガイド | 📅 計画中 |

---

## 💡 期待される効果

### 既存手法との比較

| 観点 | 戦略マッチング | 機械学習 |
|------|---------------|----------|
| 特徴量の組み合わせ | 手動定義 | 自動学習 |
| 非線形関係 | 捉えにくい | ◎ 捉えられる |
| 解釈性 | 高い | 低い（ブラックボックス） |
| 新パターンの発見 | 困難 | ◎ 自動検出 |

### 想定される改善

- **非線形パターンの検出**: 複雑な条件の組み合わせを自動学習
- **特徴量重要度**: どの要素が予測に効いているか可視化
- **データ増加に伴う精度向上**: データが増えるほどモデルが賢くなる

---

## ⚠️ 注意事項・リスク

- **データ量の要件**: 信頼性のある学習には最低90日以上のデータが推奨
- **過学習リスク**: 過去データに特化しすぎて将来予測が悪化する可能性
- **解釈性の低下**: なぜその予測になったか説明が難しい
- **運用コスト**: モデルの定期的な再訓練が必要

---

## 📊 評価指標

| 指標 | 説明 | 目標値 |
|------|------|--------|
| **RMSE** | 予測誤差（小さいほど良い） | - |
| **MAE** | 平均絶対誤差 | - |
| **予測勝率** | TOP3予測の実際の勝率 | 55%以上 |
| **予測機械割** | TOP3予測の実際の機械割 | 103%以上 |

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
