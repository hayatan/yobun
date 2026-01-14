# ヒートマップクエリ

スプレッドシートのヒートマップ機能で使用する台番別集計クエリです。

## ファイル一覧

| ファイル | 用途 |
|----------|------|
| `heatmap_query.sql` | スプレッドシート連携用ヒートマップクエリ |

## 使用方法

### スプレッドシートでの設定

1. **bqconfシートの設定**

   以下の表をbqconfシートに定義します:

   | パラメータ名 | 値の例 | 説明 |
   |-------------|--------|------|
   | @DATE_FROM | 20251217 | 集計開始日 (YYYYMMDD形式) |
   | @DATE_TO | 20260114 | 集計終了日 (YYYYMMDD形式) |
   | @HOLE | エスパス秋葉原駅前店 | 店舗名 |
   | @SPECIAL_CHECK | FALSE | 特日フィルタを有効にするか |
   | @DAY_OF_WEEK | 月 | 曜日フィルタ (月,火,水,木,金,土,日) |
   | @DAY_TYPE | 平日 | 日タイプフィルタ (平日,週末,祝日) |
   | @LAST_DIGIT | 2 | 日付末尾フィルタ (0-9) |
   | @MONTH_EQ_DAY | TRUE | 月=日フィルタ (1/1, 2/2, ... 12/12) |
   | @DOUBLE_DIGIT | TRUE | ゾロ目フィルタ (11日, 22日) |

2. **データコネクタの設定**

   - BigQueryデータコネクタを追加
   - クエリを `heatmap_query.sql` の内容に設定
   - パラメータをbqconfシートから参照

## パラメータ詳細

### 基本パラメータ

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| @DATE_FROM | STRING | 集計開始日（YYYYMMDD形式） |
| @DATE_TO | STRING | 集計終了日（YYYYMMDD形式） |
| @HOLE | STRING | 対象店舗名 |

### 特日フィルタパラメータ

`@SPECIAL_CHECK = TRUE` の場合、以下のいずれかの条件に該当する日のみ集計対象となります。

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| @SPECIAL_CHECK | BOOL | 特日フィルタを有効にするか |
| @DAY_OF_WEEK | STRING | 曜日でフィルタ（例: "月", "月,火,水"） |
| @DAY_TYPE | STRING | 日タイプでフィルタ（例: "平日", "週末,祝日"） |
| @LAST_DIGIT | STRING | 日付末尾でフィルタ（例: "2", "2,7"） |
| @MONTH_EQ_DAY | BOOL | 月と日が同じ日をフィルタ（1/1, 2/2, ..., 12/12） |
| @DOUBLE_DIGIT | BOOL | ゾロ目の日をフィルタ（11日, 22日） |

**注意**: `@SPECIAL_CHECK = FALSE` の場合、特日フィルタは適用されず全日が対象となります。

## 出力カラム

| カラム | 型 | 説明 |
|--------|-----|------|
| machine_number | INT64 | 台番 |
| machine | STRING | 機種名 |
| avg_diff | FLOAT64 | 平均差枚 |
| win_rate | FLOAT64 | 勝率 |
| date_from | STRING | 集計開始日 |
| date_to | STRING | 集計終了日 |
| payout_rate | FLOAT64 | 出玉率 |

## 台番補正

店舗のレイアウト変更に対応するため、以下の台番補正が適用されます。

### アイランド秋葉原店

- **適用期間**: 2025/11/02以前のデータ
- **補正方法**: マッピングテーブルによる変換
- **理由**: 2025/11/03のレイアウト変更により台番が大幅に変更

### エスパス秋葉原駅前店

- **適用期間**: 2025/04/20以前のデータ
- **補正方法**: 2020番台以降の台番に+2
- **理由**: 2025/04/21の増台により台番が2つずれた

## クエリ構造

```sql
WITH params AS (...)              -- 1. パラメータ定義
machine_number_mapping_island AS (...) -- 2. アイランド台番マッピング
holidays AS (...)                 -- 3. 祝日データ
ranked_data AS (...)              -- 4. 日別データ・重複排除・台番補正
aggregated_data AS (...)          -- 5. 集計データ
SELECT ...                        -- 6. 最終出力
```

## 依存関係

- **祝日判定**: `bqfunc.holidays_in_japan__us.holiday_name()` 関数を使用
- **データソース**: `yobun-450512.slot_data.data_*` テーブル

## 関連ファイル

- [datamart_machine_stats.sql](../datamart_machine_stats.sql) - 台番マッピングの参照元
