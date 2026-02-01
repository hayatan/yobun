# machine_stats データマート v2 変更履歴

このドキュメントは、machine_stats データマート v2 の変更内容、分析クエリへの影響、および新カラムの活用方法を記載しています。

---

## 変更日

2026-02-02

---

## 変更概要

### 1. 集計期間の拡張

より細かい粒度での分析を可能にするため、以下の集計期間を追加しました。

#### 追加された当日起点の集計期間

| 接頭辞 | 期間 | 用途例 |
|--------|------|--------|
| `d2_` | 当日〜1日前（2日間） | 直近の短期トレンド確認 |
| `d4_` | 当日〜3日前（4日間） | 4日サイクルの店舗分析 |
| `d6_` | 当日〜5日前（6日間） | 週間トレンドの前兆検出 |
| `d14_` | 当日〜13日前（14日間） | 2週間の中期トレンド分析 |

#### 追加された前日起点の集計期間

| 接頭辞 | 期間 | 用途例 |
|--------|------|--------|
| `prev_d4_` | 前日〜4日前（4日間） | 当日予測用の4日間実績 |
| `prev_d6_` | 前日〜6日前（6日間） | 当日予測用の6日間実績 |
| `prev_d14_` | 前日〜14日前（14日間） | 当日予測用の2週間実績 |

### 2. 日付関連カラムの追加

特日判定を分析クエリ内で毎回計算する必要がなくなり、クエリの簡素化と高速化が可能になりました。

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

## 既存分析クエリへの影響

### 影響なし

既存の分析クエリは、以前から存在するカラムのみを参照しているため、**そのまま動作します**。

変更されたのはカラムの追加のみであり、既存カラムの型、名前、計算ロジックには変更がありません。

### 推奨される更新

既存クエリで以下のような処理を行っている場合、新カラムを使用することで簡素化できます。

#### 変更前（日付カテゴリを都度計算）

```sql
SELECT
  *,
  CASE EXTRACT(DAYOFWEEK FROM target_date)
    WHEN 1 THEN '日' WHEN 2 THEN '月' WHEN 3 THEN '火'
    WHEN 4 THEN '水' WHEN 5 THEN '木' WHEN 6 THEN '金' WHEN 7 THEN '土'
  END AS day_of_week,
  CASE
    WHEN EXTRACT(DAYOFWEEK FROM target_date) IN (1, 7) THEN '週末'
    ELSE '平日'
  END AS day_type
FROM `yobun-450512.datamart.machine_stats`
```

#### 変更後（事前計算カラムを使用）

```sql
SELECT
  *,
  day_of_week_jp,  -- 新カラムをそのまま使用
  day_type         -- 祝日判定も含まれる
FROM `yobun-450512.datamart.machine_stats`
```

---

## 新カラムの活用方法

### 特日フィルタリング

```sql
-- 月と日がゾロ目の日のみ
SELECT * FROM `yobun-450512.datamart.machine_stats`
WHERE is_month_day_repdigit = TRUE;

-- 日がゾロ目（11日, 22日）のみ
SELECT * FROM `yobun-450512.datamart.machine_stats`
WHERE is_day_repdigit = TRUE;

-- 5の付く日（5, 15, 25日）
SELECT * FROM `yobun-450512.datamart.machine_stats`
WHERE target_day_last_digit = 5 OR target_day IN (5, 15, 25);

-- 7の付く日（7, 17, 27日）
SELECT * FROM `yobun-450512.datamart.machine_stats`
WHERE target_day_last_digit = 7;
```

### 曜日別分析

```sql
-- 曜日別の平均差枚を集計
SELECT
  day_of_week_jp,
  AVG(d1_diff) AS avg_diff,
  AVG(d1_payout_rate) AS avg_payout_rate
FROM `yobun-450512.datamart.machine_stats`
WHERE target_date BETWEEN '2026-01-01' AND '2026-01-31'
GROUP BY day_of_week_jp
ORDER BY CASE day_of_week_jp
  WHEN '月' THEN 1 WHEN '火' THEN 2 WHEN '水' THEN 3
  WHEN '木' THEN 4 WHEN '金' THEN 5 WHEN '土' THEN 6 WHEN '日' THEN 7
END;
```

### 平日/週末/祝日別分析

```sql
-- 日タイプ別の勝率を比較
SELECT
  day_type,
  COUNT(*) AS sample_count,
  AVG(CASE WHEN d1_diff > 0 THEN 1.0 ELSE 0.0 END) AS win_rate
FROM `yobun-450512.datamart.machine_stats`
WHERE target_date BETWEEN '2026-01-01' AND '2026-01-31'
GROUP BY day_type;
```

### 新集計期間の活用例

```sql
-- 直近2日間の連続勝率が高い台を抽出
SELECT
  hole,
  machine_number,
  machine,
  d2_win_rate,
  prev_d2_win_rate
FROM `yobun-450512.datamart.machine_stats`
WHERE target_date = '2026-02-01'
  AND d2_win_rate >= 0.5
  AND prev_d2_win_rate >= 0.5;

-- 14日間の中期トレンドで上昇傾向の台
SELECT
  hole,
  machine_number,
  machine,
  d7_payout_rate AS short_term,
  d14_payout_rate AS mid_term,
  d28_payout_rate AS long_term
FROM `yobun-450512.datamart.machine_stats`
WHERE target_date = '2026-02-01'
  AND d7_payout_rate > d14_payout_rate
  AND d14_payout_rate > d28_payout_rate;
```

---

## 解釈の変更点

### 変更なし

既存カラムの計算ロジックに変更はないため、過去の分析結果や戦略の解釈は変わりません。

### 注意事項

#### day_type の祝日判定

`day_type` カラムの祝日判定は `bqfunc.holidays_in_japan__us.holiday_name()` 関数を使用しています。

- 週末（土日）が祝日と重なる場合は「週末」として分類されます
- 振替休日も「祝日」として分類されます

従来、分析クエリ内で独自に祝日判定を行っていた場合、この仕様との差異がないか確認してください。

#### バックフィル前の既存データ

方式B（ALTER TABLE）でマイグレーションを行い、バックフィルを実行していない場合、過去データの新カラムは NULL となります。

新カラムを使用する分析では、NULL を適切に処理するか、バックフィルを実行してください。

```sql
-- NULL を考慮したクエリ例
SELECT *
FROM `yobun-450512.datamart.machine_stats`
WHERE day_type IS NOT NULL  -- バックフィル済みデータのみ
  AND day_type = '祝日';
```

---

## 今後の拡張予定

以下の機能追加を検討中です：

1. **イベント情報の統合**: `events` テーブルとの結合による LINE告知日フラグの追加
2. **連続勝敗カウント**: 連勝/連敗数のカラム追加
3. **台番位置情報**: 角台/端台などの位置情報カラム追加

---

## 参考情報

- [README.md](./README.md) - データマート詳細説明
- [MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md) - マイグレーション手順
- [sql/heatmap/heatmap_query.sql](../../heatmap/heatmap_query.sql) - 祝日判定の参考実装
