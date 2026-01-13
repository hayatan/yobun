# L+ToLOVEるダークネス 分析システム ドキュメント

## 概要

アイランド秋葉原店の「L+ToLOVEるダークネス」について、過去の機械割傾向から高設定に座れる確率を上げるための分析システムです。

本システムは以下のコンポーネントで構成されています：

1. **`datamart_machine_stats.sql`**: 生データから台番別統計データを生成するデータマート
2. **`tolove_recommendation_output.sql`**: 狙い台一覧出力（スコア計算・優先度ランク付けまでSQLで完結）
3. **`tolove_recommendation_evaluation.sql`**: 狙い台選定方法の評価（過去データでの検証）

---

## 1. データマート: `datamart_machine_stats.sql`

### 1.1 概要

生データテーブル（`yobun-450512.slot_data.data_*`）から、台番別の統計データを集計し、データマートテーブル（`yobun-450512.datamart.machine_stats`）に保存します。

### 1.2 実行方法

#### スケジュールクエリでの実行（推奨）

1. BigQueryコンソールで「スケジュールクエリ」を作成
2. クエリに `datamart_machine_stats.sql` の内容を貼り付け
3. パラメータ `@run_time` を設定（TIMESTAMP型、実行時刻が自動設定される）
4. 宛先テーブル: `yobun-450512.datamart.machine_stats`
5. 書き込み設定: 「テーブルに追加」または「上書き」

#### 手動実行

スケジュールクエリを使用しない場合、`@run_time` パラメータを手動で設定する必要があります：

```sql
SET @run_time = CURRENT_TIMESTAMP();
-- その後、datamart_machine_stats.sql の内容を実行
```

### 1.3 集計日（target_date）の決定

- **集計日 = 実行日の1日前（JST基準）**
- `DATE(@run_time, 'Asia/Tokyo') - 1` で計算
- 例: 12/25 00:00（JST）に実行 → 集計日は 12/24

### 1.4 集計期間の種類

#### 当日を含む期間（d*）

- **d1**: 当日のみ
- **d3**: 当日から3日間（当日を含む）
- **d5**: 当日から5日間（当日を含む）
- **d7**: 当日から7日間（当日を含む）
- **d28**: 当日から28日間（当日を含む）
- **mtd**: 当月1日から当日まで

#### 当日を含まない期間（prev_d*）

- **prev_d1**: 前日のみ
- **prev_d3**: 前日から3日間（当日を含まない）
- **prev_d5**: 前日から5日間（当日を含まない）
- **prev_d7**: 前日から7日間（当日を含まない）
- **prev_d28**: 前日から28日間（当日を含まない）
- **prev_mtd**: 当月1日から前日まで

### 1.5 集計項目

各期間について以下の項目を集計：

- **差枚（diff）**: 合計差枚
- **ゲーム数（game）**: 合計ゲーム数
- **勝率（win_rate）**: 勝利日数 / 総日数
- **機械割（payout_rate）**: `(ゲーム数 × 3 + 差枚) / (ゲーム数 × 3)`

### 1.6 データの重複排除

同じ日付・店舗・台番のデータが複数存在する場合、`timestamp` が最新のものを採用します。

### 1.7 台番マッピング（アイランド秋葉原店）

2025/11/02以前と2025/11/03以降で台番が変更されたため、過去データの台番を新しい台番にマッピングします。

- マッピング定義は `machine_number_mapping` CTE内に記載
- 2025/11/02以前のデータのみマッピングを適用

### 1.8 機種変更の検出

各台番について、現在の機種名で集計を開始した日（`start_date`）を算出します。これにより、機種変更前のデータを除外できます。

### 1.9 テーブル構造

```sql
CREATE TABLE `yobun-450512.datamart.machine_stats` (
  target_date DATE,              -- 集計日（パーティションキー）
  hole STRING,                   -- 店舗名
  machine_number INT64,         -- 台番
  machine STRING,                -- 機種名
  start_date DATE,              -- 集計開始日（機種変更検出用）
  end_date DATE,                -- 集計終了日
  
  -- 当日データ
  d1_diff INT64,
  d1_game INT64,
  d1_payout_rate FLOAT64,
  
  -- 当日を含む期間
  d3_diff INT64, d3_game INT64, d3_win_rate FLOAT64, d3_payout_rate FLOAT64,
  d5_diff INT64, d5_game INT64, d5_win_rate FLOAT64, d5_payout_rate FLOAT64,
  d7_diff INT64, d7_game INT64, d7_win_rate FLOAT64, d7_payout_rate FLOAT64,
  d28_diff INT64, d28_game INT64, d28_win_rate FLOAT64, d28_payout_rate FLOAT64,
  mtd_diff INT64, mtd_game INT64, mtd_win_rate FLOAT64, mtd_payout_rate FLOAT64,
  
  -- 当日を含まない期間
  prev_d1_diff INT64, prev_d1_game INT64, prev_d1_payout_rate FLOAT64,
  prev_d2_diff INT64, prev_d2_game INT64, prev_d2_win_rate FLOAT64, prev_d2_payout_rate FLOAT64,
  prev_d3_diff INT64, prev_d3_game INT64, prev_d3_win_rate FLOAT64, prev_d3_payout_rate FLOAT64,
  prev_d5_diff INT64, prev_d5_game INT64, prev_d5_win_rate FLOAT64, prev_d5_payout_rate FLOAT64,
  prev_d7_diff INT64, prev_d7_game INT64, prev_d7_win_rate FLOAT64, prev_d7_payout_rate FLOAT64,
  prev_d28_diff INT64, prev_d28_game INT64, prev_d28_win_rate FLOAT64, prev_d28_payout_rate FLOAT64,
  prev_mtd_diff INT64, prev_mtd_game INT64, prev_mtd_win_rate FLOAT64, prev_mtd_payout_rate FLOAT64
)
PARTITION BY target_date;
```

### 1.10 MERGE文による更新

- 同じ日付のデータが既に存在する場合: **上書き**
- 異なる日付のデータ: **追加**

これにより、同じ日付でクエリを再実行しても、最新のデータで上書きされます。

---

## 2. 狙い台一覧出力: `tolove_recommendation_output.sql`

### 2.1 概要

戦略シミュレーションからスコア計算・優先度ランク付けまでをSQLで完結させた出力クエリです。BigQuery Connectorでスプレッドシートに接続し、フィルタ機能で必要なデータを絞り込みます。

### 2.2 パラメータ設定

```sql
DECLARE target_date DATE DEFAULT NULL;  -- 推奨台を出す日付（NULL=最新日の次の日）
DECLARE target_hole STRING DEFAULT 'アイランド秋葉原店';  -- 対象店舗
DECLARE target_machine STRING DEFAULT 'L+ToLOVEるダークネス';  -- 対象機種
```

### 2.3 スコア計算方法

`rms_frequency_dual` 方式を採用しています：

```
総合スコア = RMS × 頻度ボーナス × 複合ボーナス
```

- **RMS**: 勝率パーセンタイルスコアと機械割パーセンタイルスコアの二乗平均平方根
- **頻度ボーナス**: `sqrt(該当数) / sqrt(最大該当数)`
- **複合ボーナス**: 機械割がp50以上かつ勝率がp50以上の場合 1.1、それ以外 1.0

### 2.4 優先度ランクの定義

| ランク | 条件 | 期待値 |
|--------|------|--------|
| 5 | TOP1スコアの99%以上 | 勝率63%、機械割113% |
| 4 | TOP1スコアの97%以上 | 勝率60%、機械割110% |
| 3 | TOP1スコアの95%以上 | 勝率56%、機械割108% |
| 2 | TOP1スコアの90%以上 | 勝率50%、機械割106% |
| 1 | TOP1スコアの80%以上 | 参考程度 |
| 0 | それ以外 | 対象外 |

### 2.5 出力項目

| カラム | 型 | 説明 |
|--------|-----|------|
| `target_date` | DATE | 推奨日付 |
| `machine_number` | STRING | 台番 |
| `priority_rank` | INT | 優先度ランク（5=最高、0=対象外） |
| `total_score` | FLOAT | 総合スコア |
| `top1_ratio` | FLOAT | TOP1スコアとの比率（0〜1） |
| `rank` | INT | 順位 |
| `match_count` | INT | 該当戦略数 |
| `weighted_payout_rate` | FLOAT | 重み付け機械割（例: 1.085 = 108.5%） |
| `weighted_win_rate` | FLOAT | 重み付け勝率（例: 0.583 = 58.3%） |
| `rms` | FLOAT | RMSスコア |
| `frequency_bonus` | FLOAT | 出現頻度ボーナス |
| `dual_high_bonus` | FLOAT | 複合ボーナス |
| `top1_score` | FLOAT | TOP1のスコア（参考） |

### 2.6 BigQuery Connectorでの使い方

1. **BigQuery Connectorで接続**
   - スプレッドシートの「データ」→「データコネクタ」→「BigQuery に接続」
   - プロジェクト: `yobun-450512`
   - データセット: `(SQLクエリ)`
   - クエリ: `tolove_recommendation_output.sql` の内容を貼り付け
   - 接続先シート: 任意のシート名（例: 「狙い台一覧」）

2. **フィルタで絞り込み**
   - `priority_rank >= 3` で優先度3以上のみ表示
   - `top1_ratio >= 0.95` でTOP1比率95%以上のみ表示
   - など、必要に応じてフィルタを設定

3. **条件付き書式で色付け（オプション）**
   - `priority_rank` 列に条件付き書式を設定
   - 5 → 金色、4 → 銀色、3 → 銅色、など

---

## 3. 評価クエリ: `tolove_recommendation_evaluation.sql`

### 3.1 概要

過去の各日付で狙い台選定ロジックを適用し、実際のパフォーマンスを評価するクエリです。各スコア計算方法（score_method）の比較や、しきい値別の精度検証ができます。

### 3.2 パラメータ設定

```sql
DECLARE target_hole STRING DEFAULT 'アイランド秋葉原店';
DECLARE target_machine STRING DEFAULT 'L+ToLOVEるダークネス';
DECLARE evaluation_days INT64 DEFAULT 120;  -- 評価期間（直近N日間）
```

### 3.3 評価カテゴリ

| カテゴリ | 説明 |
|----------|------|
| TOP1〜TOP5 | スコア上位N台 |
| OUTLIER | 外れ値（飛び抜けて高いスコアの台） |
| THRESHOLD_80〜99PCT | TOP1スコアの各%以上 |

### 3.4 スコア計算方法（score_method）

| 方法 | 説明 |
|------|------|
| `original` | RMS × 信頼性 × 頻度 × 異常値 × 複合 |
| `simple` | RMSのみ |
| `rms_reliability` | RMS × 信頼性（絶対閾値ベース） |
| `rms_frequency` | RMS × 頻度ボーナス |
| `rms_frequency_dual` | RMS × 頻度 × 複合ボーナス（推奨） |
| `rms_frequency_anomaly` | RMS × 頻度 × 異常値ボーナス |
| `strategy_filter` | 有効性スコア0.5以上の戦略のみ |
| `rms_frequency_filter` | RMS × 頻度 + 戦略フィルタ |

### 3.5 出力項目

| カラム | 説明 |
|--------|------|
| `score_method` | スコア計算方法 |
| `result_key` | 評価カテゴリ（TOP1, THRESHOLD_95PCT等） |
| `evaluation_days` | 評価日数 |
| `total_machines` | 総台数 |
| `avg_machines_per_day` | 1日あたり平均台数 |
| `win_rate` | 勝率（%） |
| `payout_rate` | 機械割（%） |
| `total_diff` | 合計差枚 |
| `avg_diff` | 平均差枚 |
| `max_diff` / `min_diff` | 最大/最小差枚 |

---

## 4. クエリファイル一覧

### 分析クエリ

| ファイル | 用途 |
|----------|------|
| `tolove_recommendation_output.sql` | 狙い台一覧出力（スコア計算・優先度ランク付けまでSQLで完結） |
| `tolove_recommendation_evaluation.sql` | 狙い台選定方法の評価（過去データでの検証） |

### データマート

| ファイル | 用途 |
|----------|------|
| `datamart_machine_stats.sql` | 生データから台番別統計データを生成 |

---

## 5. ワークフロー

### 5.1 日常的な運用フロー

1. **データマートの更新**（毎日自動実行）
   - `datamart_machine_stats.sql` をスケジュールクエリで実行
   - 前日のデータが `datamart.machine_stats` に追加/更新される

2. **狙い台一覧の取得**（手動実行）
   - BigQuery Connectorで `tolove_recommendation_output.sql` をスプレッドシートに接続
   - フィルタ機能で `priority_rank >= 3` など必要な条件を設定

3. **台選び**
   - `priority_rank` が高い台（5=最優先、4=高優先など）を狙う
   - `top1_ratio` が0.95以上の台を優先的に検討

### 5.2 評価・検証ワークフロー

1. **評価クエリの実行**
   - `tolove_recommendation_evaluation.sql` をBigQueryで実行
   - 各score_method、各しきい値の精度を比較

2. **最適なパラメータの選定**
   - `rms_frequency_dual` + `THRESHOLD_95PCT以上` が推奨
   - 勝率56%以上、機械割108%以上が期待できる

### 5.3 パラメータの調整

各クエリのパラメータを調整することで、以下のことが可能です：

- **特定の日付の推奨台を取得**: `DECLARE target_date DATE DEFAULT '2026-01-15';`
- **別の店舗・機種を分析**: `DECLARE target_hole` と `DECLARE target_machine` を変更
- **評価期間の変更**: `DECLARE evaluation_days INT64 DEFAULT 120;`

---

## 6. 注意事項

### 6.1 データの整合性

- `datamart_machine_stats.sql` は毎日実行することを推奨します
- 同じ日付で再実行すると、既存データが上書きされます

### 6.2 スコアリングの調整

スコア計算方法を変更したい場合は、`tolove_recommendation_output.sql` のスコア計算部分を編集してください。

---

## 7. トラブルシューティング

### 7.1 データマートが更新されない

- スケジュールクエリの設定を確認
- `@run_time` パラメータが正しく設定されているか確認
- エラーログを確認

### 7.2 狙い台一覧が出力されない

- `datamart.machine_stats` に最新のデータが存在するか確認
- `tolove_recommendation_output.sql` のパラメータ（`target_hole`, `target_machine`）を確認
- BigQuery Connectorの接続設定を確認
