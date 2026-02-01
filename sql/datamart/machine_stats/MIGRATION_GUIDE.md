# machine_stats データマート v2 マイグレーションガイド

このドキュメントは、machine_stats データマートを v2（拡張版）に移行するためのオペレーター向け作業手順書です。

## 変更概要

### 追加された集計期間

**当日から（当日を含む）**:
- `d2_*` - 当日〜1日前（2日間）
- `d4_*` - 当日〜3日前（4日間）
- `d6_*` - 当日〜5日前（6日間）
- `d14_*` - 当日〜13日前（14日間）

**前日から（当日を含まない）**:
- `prev_d4_*` - 前日〜4日前（4日間）
- `prev_d6_*` - 前日〜6日前（6日間）
- `prev_d14_*` - 前日〜14日前（14日間）

### 追加された日付カラム

| カラム | 型 | 説明 |
|--------|------|------|
| `target_year` | INT64 | 年 |
| `target_month` | INT64 | 月 |
| `target_day` | INT64 | 日 |
| `target_day_last_digit` | INT64 | 日の下1桁 (0-9) |
| `is_month_day_repdigit` | BOOL | 月と日がゾロ目か (01/01, 02/02, ..., 12/12) |
| `is_day_repdigit` | BOOL | 日がゾロ目か (11, 22) |
| `day_of_week_jp` | STRING | 曜日（日本語: 月,火,水,木,金,土,日） |
| `day_type` | STRING | 平日/週末/祝日 |

---

## 移行手順

### 方式A: テーブル再作成（推奨）

既存データを一度削除し、テーブルを再作成後にバックフィルを実行する方式です。

#### 手順1: 既存テーブルの削除

BigQueryコンソールで以下を実行:

```sql
DROP TABLE IF EXISTS `yobun-450512.datamart.machine_stats`;
```

#### 手順2: 新テーブルの作成

`create_table.sql` の内容をBigQueryコンソールで実行します。

#### 手順3: スケジュールクエリの更新

1. BigQueryコンソールで「スケジュールされたクエリ」を開く
2. 既存の `machine_stats` 更新クエリを編集
3. `query.sql` の内容で置き換え
4. 保存

#### 手順4: バックフィルの実行

過去データを再生成します。

**方法A: APIエンドポイント経由**

```bash
curl -X POST http://localhost:8080/api/datamart/run \
  -H "Content-Type: application/json" \
  -d '{"startDate": "2025-01-01", "endDate": "2026-02-01"}'
```

**方法B: BigQueryコンソールで手動実行**

各日付に対して、`@run_time` パラメータを指定してクエリを実行します。

例: 2026-01-15 のデータを生成する場合
- `@run_time` = `2026-01-16T00:00:00+09:00` を指定
- （target_date = DATE(@run_time, 'Asia/Tokyo') - 1日 = 2026-01-15）

---

### 方式B: ALTER TABLEによる追加

既存データを保持しながらカラムを追加する方式です。既存データの新カラムはNULLとなります。

#### 手順1: カラムの追加

BigQueryコンソールで以下を実行:

```sql
-- 日付関連カラム
ALTER TABLE `yobun-450512.datamart.machine_stats`
ADD COLUMN IF NOT EXISTS target_year INT64 OPTIONS(description = '年'),
ADD COLUMN IF NOT EXISTS target_month INT64 OPTIONS(description = '月'),
ADD COLUMN IF NOT EXISTS target_day INT64 OPTIONS(description = '日'),
ADD COLUMN IF NOT EXISTS target_day_last_digit INT64 OPTIONS(description = '日の下1桁'),
ADD COLUMN IF NOT EXISTS is_month_day_repdigit BOOL OPTIONS(description = '月と日がゾロ目か'),
ADD COLUMN IF NOT EXISTS is_day_repdigit BOOL OPTIONS(description = '日がゾロ目か'),
ADD COLUMN IF NOT EXISTS day_of_week_jp STRING OPTIONS(description = '曜日（日本語）'),
ADD COLUMN IF NOT EXISTS day_type STRING OPTIONS(description = '平日/週末/祝日');

-- d2 集計期間
ALTER TABLE `yobun-450512.datamart.machine_stats`
ADD COLUMN IF NOT EXISTS d2_diff INT64 OPTIONS(description = '当日から2日間 総差枚'),
ADD COLUMN IF NOT EXISTS d2_game INT64 OPTIONS(description = '当日から2日間 総ゲーム数'),
ADD COLUMN IF NOT EXISTS d2_win_rate FLOAT64 OPTIONS(description = '当日から2日間 勝率'),
ADD COLUMN IF NOT EXISTS d2_payout_rate FLOAT64 OPTIONS(description = '当日から2日間 機械割');

-- d4 集計期間
ALTER TABLE `yobun-450512.datamart.machine_stats`
ADD COLUMN IF NOT EXISTS d4_diff INT64 OPTIONS(description = '当日から4日間 総差枚'),
ADD COLUMN IF NOT EXISTS d4_game INT64 OPTIONS(description = '当日から4日間 総ゲーム数'),
ADD COLUMN IF NOT EXISTS d4_win_rate FLOAT64 OPTIONS(description = '当日から4日間 勝率'),
ADD COLUMN IF NOT EXISTS d4_payout_rate FLOAT64 OPTIONS(description = '当日から4日間 機械割');

-- d6 集計期間
ALTER TABLE `yobun-450512.datamart.machine_stats`
ADD COLUMN IF NOT EXISTS d6_diff INT64 OPTIONS(description = '当日から6日間 総差枚'),
ADD COLUMN IF NOT EXISTS d6_game INT64 OPTIONS(description = '当日から6日間 総ゲーム数'),
ADD COLUMN IF NOT EXISTS d6_win_rate FLOAT64 OPTIONS(description = '当日から6日間 勝率'),
ADD COLUMN IF NOT EXISTS d6_payout_rate FLOAT64 OPTIONS(description = '当日から6日間 機械割');

-- d14 集計期間
ALTER TABLE `yobun-450512.datamart.machine_stats`
ADD COLUMN IF NOT EXISTS d14_diff INT64 OPTIONS(description = '当日から14日間 総差枚'),
ADD COLUMN IF NOT EXISTS d14_game INT64 OPTIONS(description = '当日から14日間 総ゲーム数'),
ADD COLUMN IF NOT EXISTS d14_win_rate FLOAT64 OPTIONS(description = '当日から14日間 勝率'),
ADD COLUMN IF NOT EXISTS d14_payout_rate FLOAT64 OPTIONS(description = '当日から14日間 機械割');

-- prev_d4 集計期間
ALTER TABLE `yobun-450512.datamart.machine_stats`
ADD COLUMN IF NOT EXISTS prev_d4_diff INT64 OPTIONS(description = '前日から4日間 総差枚'),
ADD COLUMN IF NOT EXISTS prev_d4_game INT64 OPTIONS(description = '前日から4日間 総ゲーム数'),
ADD COLUMN IF NOT EXISTS prev_d4_win_rate FLOAT64 OPTIONS(description = '前日から4日間 勝率'),
ADD COLUMN IF NOT EXISTS prev_d4_payout_rate FLOAT64 OPTIONS(description = '前日から4日間 機械割');

-- prev_d6 集計期間
ALTER TABLE `yobun-450512.datamart.machine_stats`
ADD COLUMN IF NOT EXISTS prev_d6_diff INT64 OPTIONS(description = '前日から6日間 総差枚'),
ADD COLUMN IF NOT EXISTS prev_d6_game INT64 OPTIONS(description = '前日から6日間 総ゲーム数'),
ADD COLUMN IF NOT EXISTS prev_d6_win_rate FLOAT64 OPTIONS(description = '前日から6日間 勝率'),
ADD COLUMN IF NOT EXISTS prev_d6_payout_rate FLOAT64 OPTIONS(description = '前日から6日間 機械割');

-- prev_d14 集計期間
ALTER TABLE `yobun-450512.datamart.machine_stats`
ADD COLUMN IF NOT EXISTS prev_d14_diff INT64 OPTIONS(description = '前日から14日間 総差枚'),
ADD COLUMN IF NOT EXISTS prev_d14_game INT64 OPTIONS(description = '前日から14日間 総ゲーム数'),
ADD COLUMN IF NOT EXISTS prev_d14_win_rate FLOAT64 OPTIONS(description = '前日から14日間 勝率'),
ADD COLUMN IF NOT EXISTS prev_d14_payout_rate FLOAT64 OPTIONS(description = '前日から14日間 機械割');
```

#### 手順2: スケジュールクエリの更新

方式Aの手順3と同様。

#### 手順3: バックフィルの実行（任意）

既存データに新カラムの値を設定したい場合は、方式Aの手順4と同様にバックフィルを実行します。

---

## 確認手順

### テーブル構造の確認

```sql
SELECT column_name, data_type, description
FROM `yobun-450512.datamart.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`
WHERE table_name = 'machine_stats'
ORDER BY ordinal_position;
```

### データの確認

```sql
SELECT 
  target_date,
  hole,
  machine_number,
  target_year,
  target_month,
  target_day,
  day_of_week_jp,
  day_type,
  d2_diff,
  d4_diff,
  d6_diff,
  d14_diff
FROM `yobun-450512.datamart.machine_stats`
WHERE target_date = '2026-02-01'
LIMIT 10;
```

---

## ロールバック手順

問題が発生した場合は、以下の手順でロールバックできます。

### 方式Aを実行した場合

1. 新テーブルを削除
2. 旧バージョンの `create_table.sql` でテーブル再作成
3. 旧バージョンの `query.sql` でスケジュールクエリを更新
4. バックフィルを実行

### 方式Bを実行した場合

1. スケジュールクエリを旧バージョンに戻す
2. 追加したカラムは残しても問題なし（使用されないだけ）

---

## トラブルシューティング

### 祝日判定が正しく動作しない

`bqfunc.holidays_in_japan__us.holiday_name()` 関数が利用可能か確認してください。

```sql
SELECT bqfunc.holidays_in_japan__us.holiday_name(DATE('2026-01-01'));
-- → '元日' が返れば正常
```

### バックフィルが途中で失敗する

APIエンドポイントでタイムアウトが発生する場合は、日付範囲を分割して実行してください。

```bash
# 1ヶ月ずつ実行
curl -X POST http://localhost:8080/api/datamart/run \
  -H "Content-Type: application/json" \
  -d '{"startDate": "2025-01-01", "endDate": "2025-01-31"}'

curl -X POST http://localhost:8080/api/datamart/run \
  -H "Content-Type: application/json" \
  -d '{"startDate": "2025-02-01", "endDate": "2025-02-28"}'
# ...
```

---

## 参考情報

- [README.md](./README.md) - データマート詳細説明
- [CHANGELOG_v2.md](./CHANGELOG_v2.md) - 変更履歴と分析クエリへの影響
