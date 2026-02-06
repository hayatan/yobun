# SQL ファイル修正ガイドライン

> 全体的なプロジェクトガイドラインは [CLAUDE.md](../CLAUDE.md) を参照してください。

## ディレクトリ構造

```
sql/
├── AGENTS.md                          # このファイル（修正ガイドライン）
├── raw_data/                          # 元データ管理ディレクトリ
│   ├── README.md                      # 元データのドキュメント
│   ├── schema.js                      # 共通スキーマ定義（SQLite/BQ両対応）
│   ├── create_raw_data_table.sql     # BigQuery DDL
│   └── migrations/                    # マイグレーションファイル
│       ├── README.md                  # マイグレーション手順書
│       └── 001_add_source_column.*.sql
├── datamart/                          # データマートディレクトリ
│   └── machine_stats/
│       ├── query.sql                  # データマート生成クエリ
│       ├── create_table.sql           # データマートテーブル作成DDL
│       ├── README.md                  # データマートのドキュメント
│       ├── MIGRATION_GUIDE.md         # マイグレーションガイド
│       └── CHANGELOG_v2.md            # 変更履歴
├── machine_summary/                   # 機種サマリークエリ
│   ├── machine_summary.sql
│   └── README.md
├── heatmap/                           # ヒートマップクエリ
│   ├── heatmap_query.sql
│   └── README.md
├── scrape_failures/                   # 失敗記録スキーマ
│   └── schema.js
├── manual_corrections/                # 手動補正スキーマ
│   └── schema.js
├── events/                            # イベントスキーマ
│   └── schema.js
├── event_types/                       # イベントタイプスキーマ
│   └── schema.js
└── analysis/                          # 分析クエリディレクトリ
    ├── README.md                      # 分析システムのドキュメント
    ├── simple_prediction/             # シンプル予測クエリ
    │   ├── 01_day_category_effect.sql
    │   ├── 02_streak_effect.sql
    │   ├── 03_combined_strategy.sql
    │   ├── 04_recommendation_output.sql
    │   └── README.md
    └── strategy_matching/             # 戦略マッチングクエリ
        ├── recommendation_output.sql
        ├── recommendation_evaluation.sql
        ├── scripts/
        └── results/
```

---

## データフロー概要

```
スクレイピング → SQLite（raw_data） → BigQuery（raw_data） → データマート → 分析クエリ
```

- **元データ（raw_data）**: スクレイピングで取得した生データ
  - 定義: `sql/raw_data/schema.js`
  - 格納先: SQLite（scraped_data）、BigQuery（data_YYYYMMDD）
- **データマート**: 元データを集計した分析用データ
  - 定義: `sql/datamart/machine_stats/create_table.sql`
  - 生成: `sql/datamart/machine_stats/query.sql`
- **分析クエリ**: データマートを参照する分析SQL
  - 配置: `sql/analysis/`

---

## 基本原則

### 1. 整合性の維持

- **データマートの変更時**: `datamart/machine_stats/query.sql` を変更したら、必ず `analysis/README.md` の「1. データマート」セクションを更新する
- **分析クエリの変更時**: `analysis/*.sql` を変更したら、必ず `analysis/README.md` の該当セクションを更新する
- **新規クエリ追加時**: `analysis/README.md` の「4. クエリファイル一覧」に追加する

### 2. ドキュメントの更新

- クエリの動作や仕様を変更した場合は、必ず `analysis/README.md` を更新する
- 新しい機能を追加した場合は、使用方法を `analysis/README.md` に追記する
- パラメータを追加・変更した場合は、`analysis/README.md` に記載する

### 3. コメントの記述

- 複雑なロジックには必ずコメントを記述する
- CTE（Common Table Expression）には目的を記載する
- パラメータの説明はクエリ冒頭に記載する

---

## 元データ（Raw Data）の修正方法

### `raw_data/schema.js` を修正する場合

元データのスキーマを変更する場合の手順：

#### 1. スキーマ変更の種類

##### カラムの追加
1. **`raw_data/schema.js` の修正**
   - `columns` 配列に新しいカラムを追加
   - `bqType`、`sqliteType`、`description` を定義

2. **マイグレーションファイルの作成**
   - `raw_data/migrations/` に新しいマイグレーションファイルを追加
   - SQLite用: `NNN_description.sqlite.sql`
   - BigQuery用: `NNN_description.bq.sql`
   - 手順書: `migrations/README.md` に実行方法を追記

3. **マイグレーションの実行**
   - 手順書に従ってSQLite/BigQueryのマイグレーションを実行

4. **アプリケーションコードの修正**
   - `src/db/bigquery/operations.js` で新カラムを使用
   - `src/db/sqlite/operations.js` で新カラムを使用

##### ID生成ロジックの変更
1. **`raw_data/schema.js` の `generateId` 関数を修正**
2. **既存データへの影響を確認**
   - IDが変わると重複チェックに影響
   - 必要に応じてデータ移行を検討

#### 2. チェックリスト

元データスキーマを修正したら、以下を確認：

- [ ] `raw_data/schema.js` が正しい構文か
- [ ] マイグレーションファイルが作成されているか
- [ ] `migrations/README.md` に実行方法が記載されているか
- [ ] `raw_data/README.md` が最新か
- [ ] アプリケーションコード（`src/db/*/operations.js`）が更新されているか
- [ ] データマート生成クエリ（`datamart/machine_stats/query.sql`）が影響を受けないか

---

## データマートの修正方法

### `datamart/machine_stats/query.sql` を修正する場合

#### 1. 集計期間の追加

新しい集計期間（例: `d14`、`prev_d14`）を追加する場合：

1. **`datamart/machine_stats/query.sql` の修正**
   - `stats_d14` CTE を追加（`stats_d3` などを参考）
   - `stats_prev_d14` CTE を追加（`stats_prev_d3` などを参考）
   - 最終SELECT文に `d14_*` と `prev_d14_*` カラムを追加
   - MERGE文のUPDATEとINSERTにカラムを追加

2. **`datamart/machine_stats/create_table.sql` の修正**
   - テーブル定義に `d14_*` と `prev_d14_*` カラムを追加

3. **`analysis/README.md` の更新**
   - 「1.4 集計期間の種類」セクションに新しい期間を追加
   - 「1.9 テーブル構造」セクションに新しいカラムを追加

#### 2. 集計項目の追加

新しい集計項目（例: `big_count`、`reg_count`）を追加する場合：

1. **`datamart/machine_stats/query.sql` の修正**
   - 各 `stats_*` CTE で新しい項目を集計
   - 最終SELECT文にカラムを追加
   - MERGE文のUPDATEとINSERTにカラムを追加

2. **`datamart/machine_stats/create_table.sql` の修正**
   - テーブル定義に新しいカラムを追加

3. **`analysis/README.md` の更新**
   - 「1.5 集計項目」セクションに新しい項目を追加
   - 「1.9 テーブル構造」セクションに新しいカラムを追加

#### 3. 台番マッピングの追加

新しい店舗の台番マッピングを追加する場合：

1. **`datamart/machine_stats/query.sql` の修正**
   - `machine_number_mapping` CTE に新しい店舗のマッピングを追加
   - `normalized_data` CTE のCASE文に新しい店舗の条件を追加

2. **`analysis/README.md` の更新**
   - 「1.7 台番マッピング」セクションに新しい店舗の説明を追加

#### 4. チェックリスト

データマートを修正したら、以下を確認：

- [ ] `datamart/machine_stats/query.sql` が正しく動作するか（構文エラーがないか）
- [ ] `datamart/machine_stats/create_table.sql` のテーブル定義と一致しているか
- [ ] `analysis/README.md` の「1. データマート」セクションが最新か
- [ ] 既存の分析クエリ（`analysis/*.sql`）が影響を受けないか

---

## 分析クエリの作成・修正方法

### 新しく分析クエリを作成する場合

#### 1. ファイルの配置

- 分析クエリは `sql/analysis/` ディレクトリ配下のサブディレクトリに配置する
- ファイル名は `snake_case` で、機能を表す明確な名前を使用する
- 例: `trend_analysis.sql`、`machine_comparison.sql`

#### 2. クエリの構造

```sql
-- ============================================================================
-- [クエリ名]
-- ============================================================================
--
-- 【パラメータ定義】
--   以下のDECLARE文で定義した値を使用
-- ============================================================================
DECLARE target_hole STRING DEFAULT 'アイランド秋葉原店';
DECLARE target_machine STRING DEFAULT 'L+ToLOVEるダークネス';

-- 【分析目的】
--   このクエリで何を分析するかを記載

-- 【出力項目】
--   出力されるカラムとその意味を記載

-- ============================================================================

WITH
-- 基本データの取得
base_data AS (
  SELECT ...
  FROM `yobun-450512.datamart.machine_stats`
  WHERE ...
),

-- 分析処理
analysis_result AS (
  SELECT ...
  FROM base_data
  ...
)

-- 最終出力
SELECT ...
FROM analysis_result
ORDER BY ...
```

#### 3. データマートの参照

- 分析クエリは `yobun-450512.datamart.machine_stats` テーブルを参照する
- 生データテーブル（`yobun-450512.scraped_data.data_*`）は直接参照しない
- 集計期間は `prev_d*`（当日を含まない）と `d*`（当日を含む）を適切に使い分ける

#### 4. README の更新

1. **`analysis/README.md` の「4. クエリファイル一覧」に追加**
   ```markdown
   | ファイル | 用途 |
   |----------|------|
   | `new_analysis.sql` | 新しい分析の説明 |
   ```

2. **必要に応じて新しいセクションを追加**
   - クエリの使い方
   - パラメータの説明
   - 出力項目の説明
   - 使用例

#### 5. チェックリスト

新しい分析クエリを作成したら、以下を確認：

- [ ] クエリが正しく動作するか（構文エラーがないか）
- [ ] データマートのカラム名が正しいか
- [ ] パラメータの説明がクエリ冒頭に記載されているか
- [ ] `analysis/README.md` に追加されているか
- [ ] 出力項目の説明が記載されているか

### 既存の分析クエリを修正する場合

#### 1. パラメータの追加・変更

1. **クエリの修正**
   - `DECLARE` 文を追加・変更
   - クエリ冒頭のコメントにパラメータの説明を追加

2. **`analysis/README.md` の更新**
   - 該当クエリのセクションでパラメータの説明を更新

#### 2. 出力項目の追加・変更

1. **クエリの修正**
   - SELECT文に新しいカラムを追加
   - 必要に応じてCTEを追加・修正

2. **`analysis/README.md` の更新**
   - 該当クエリのセクションで出力項目の説明を更新

#### 3. ロジックの変更

1. **クエリの修正**
   - 変更箇所にコメントを追加（なぜ変更したか）

2. **`analysis/README.md` の更新**
   - 変更内容を反映
   - 動作が変わった場合は、使い方の説明も更新

#### 4. チェックリスト

既存の分析クエリを修正したら、以下を確認：

- [ ] クエリが正しく動作するか（構文エラーがないか）
- [ ] 既存の出力形式と互換性があるか（破壊的変更の場合は明記）
- [ ] `analysis/README.md` が最新か
- [ ] 変更内容がコメントに記載されているか

---

## README の更新方法

### `analysis/README.md` を更新する場合

#### 1. データマート関連の更新

- **セクション**: 「1. データマート」
- **更新タイミング**: `datamart/machine_stats/query.sql` または `datamart/machine_stats/create_table.sql` を変更した時
- **確認項目**:
  - 集計期間の説明が最新か
  - 集計項目の説明が最新か
  - テーブル構造が最新か
  - 実行方法が正しいか

#### 2. 分析クエリ関連の更新

- **セクション**: 「2. 戦略シミュレーション + 台番推薦」など、各クエリのセクション
- **更新タイミング**: `analysis/*.sql` を変更した時
- **確認項目**:
  - パラメータの説明が最新か
  - 出力項目の説明が最新か
  - 使い方が正しいか
  - クエリの構造が最新か

#### 3. 新規クエリ追加時の更新

- **セクション**: 「4. クエリファイル一覧」と新しいセクション
- **更新タイミング**: 新しい分析クエリを追加した時
- **確認項目**:
  - ファイル一覧に追加されているか
  - 使い方の説明が記載されているか
  - パラメータの説明が記載されているか
  - 出力項目の説明が記載されているか

#### 4. 整合性チェック

README を更新したら、以下を確認：

- [ ] 記載されているファイル名が実際に存在するか
- [ ] 記載されているカラム名が実際のテーブル定義と一致しているか
- [ ] 記載されているパラメータ名が実際のクエリと一致しているか
- [ ] 記載されている実行方法が正しいか
- [ ] 記載されている出力項目が実際のクエリの出力と一致しているか

---

## ベストプラクティス

### 1. 変更前の確認

- 変更を加える前に、既存のコードとドキュメントを確認する
- 影響範囲を把握する（他のクエリへの影響がないか）

### 2. 段階的な変更

- 大きな変更は小さな変更に分割する
- 各変更ごとに動作確認とドキュメント更新を行う

### 3. コメントの記述

- 複雑なロジックには必ずコメントを記述する
- 変更理由をコメントに記載する（特に既存ロジックを変更する場合）

### 4. テスト

- クエリを修正したら、必ず実行して動作確認する
- 出力結果が期待通りか確認する
- エラーが発生しないか確認する

### 5. ドキュメントの同期

- クエリの変更と同時にドキュメントも更新する
- 後回しにしない（忘れやすいため）

---

## トラブルシューティング

### よくある問題と対処法

#### 1. データマートのカラムが見つからない

- **原因**: テーブル定義とクエリのカラム名が不一致
- **対処**: `datamart/machine_stats/create_table.sql` のテーブル定義を確認し、正しいカラム名を使用する

#### 2. 分析クエリがエラーになる

- **原因**: データマートのカラム名が変更された、または存在しない
- **対処**: `datamart/machine_stats/query.sql` の最新のカラム定義を確認する

#### 3. README と実際の動作が違う

- **原因**: クエリを変更したが README を更新し忘れた
- **対処**: README を最新の状態に更新する

#### 4. パラメータが効かない

- **原因**: `DECLARE` 文の記述が間違っている、またはスコープが違う
- **対処**: `DECLARE` 文の位置と記述を確認する

---

## チェックリスト（変更時の最終確認）

クエリやドキュメントを変更したら、以下を確認：

### データマートの変更時

- [ ] `datamart/machine_stats/query.sql` が正しく動作する
- [ ] `datamart/machine_stats/create_table.sql` のテーブル定義と一致している
- [ ] `analysis/README.md` の「1. データマート」セクションが最新
- [ ] 既存の分析クエリが影響を受けない

### 分析クエリの変更時

- [ ] クエリが正しく動作する（構文エラーがない）
- [ ] データマートのカラム名が正しい
- [ ] パラメータの説明がクエリ冒頭に記載されている
- [ ] `analysis/README.md` が最新
- [ ] 出力項目の説明が記載されている

### 新規クエリ追加時

- [ ] クエリが正しく動作する
- [ ] データマートのカラム名が正しい
- [ ] パラメータの説明がクエリ冒頭に記載されている
- [ ] `analysis/README.md` の「4. クエリファイル一覧」に追加されている
- [ ] 使い方の説明が `analysis/README.md` に記載されている

---

## 参考資料

- `analysis/README.md`: 分析システムの詳細ドキュメント
- `datamart/machine_stats/query.sql`: データマート生成クエリの実装例
- `analysis/strategy_matching/recommendation_output.sql`: 分析クエリの実装例
- `analysis/strategy_matching/recommendation_evaluation.sql`: 評価クエリの実装例
