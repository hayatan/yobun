# シンプル狙い台予測

> 個別戦略の効果を検証しながら、シンプルな狙い台予測システムを構築する。

## 概要

`strategy_matching` は約200以上の戦略を複合させており、ノイズになる可能性がある。
このディレクトリでは、個別の戦略を検証し、有効性が確認できたものだけを採用するアプローチを取る。

## 検証対象

- **店舗**: アイランド秋葉原店
- **機種**: L+ToLOVEるダークネス（設置台数が多く、台移動も少ないため検証対象としてベスト）

## 日付カテゴリの構成

LINE告知は別格で強い日のため、以下の優先順位でカテゴリ分類：

| 優先順 | カテゴリ | 条件 | ソース |
|--------|----------|------|--------|
| 1 | LINE告知 | eventsテーブルにイベントあり | `scraped_data.events` |
| 2 | 月末 | LAST_DAY(target_date) | ハードコード |
| 3 | 0のつく日 | 日付末尾が0（10, 20, 30日） | ハードコード |
| 4 | 1のつく日 | 日付末尾が1（1, 11, 21, 31日） | ハードコード |
| 5 | 6のつく日 | 日付末尾が6（6, 16, 26日） | ハードコード |
| 6 | 8のつく日 | 日付末尾が8（8, 18, 28日） | ハードコード |
| 7 | 9のつく日 | 日付末尾が9（9, 19, 29日） | ハードコード |
| 8 | 通常日 | 上記以外の日 | - |

※ 重複する場合は優先順位の高いカテゴリが適用される（例: 30日は「月末」、31日は「月末」）

## 連勝/連敗パターン

| パターン | 判定条件 |
|----------|----------|
| 2連勝 | prev_d2_win_rate = 1.0 |
| 2連敗 | prev_d2_win_rate = 0.0 |
| 3連勝 | prev_d3_win_rate = 1.0 |
| 3連敗 | prev_d3_win_rate = 0.0 |
| 5連勝 | prev_d5_win_rate = 1.0 |
| 5連敗 | prev_d5_win_rate = 0.0 |

※ 4連勝/4連敗は `datamart.machine_stats` に対応カラムがないため省略

## クエリファイル

| ファイル | 説明 | ステータス |
|----------|------|------------|
| `01_day_category_effect.sql` | 日付カテゴリ別効果検証（8カテゴリ版） | 実装済 |
| `02_streak_effect.sql` | 連勝/連敗効果検証（2,3,5連勝/連敗版） | 実装済 |
| `03_combined_strategy.sql` | 組み合わせ戦略の検証（すべての日を含む） | 実装済 |
| `04_recommendation_output.sql` | 狙い台出力クエリ | 実装済 |
| `results/evaluation_2026-02-01.md` | 検証結果と考察（技術向け） | 完了 |
| `results/tolove_tips.md` | 狙い目まとめ（友達向け） | 完了 |

## 使い方

### 1. 日付カテゴリ別効果検証

BigQueryコンソールで `01_day_category_effect.sql` を実行。

```sql
-- パラメータを変更する場合
DECLARE target_hole STRING DEFAULT 'アイランド秋葉原店';
DECLARE target_machine STRING DEFAULT 'L+ToLOVEるダークネス';
DECLARE eval_start_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 360 DAY);
DECLARE eval_end_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);
```

### 2. 連勝/連敗効果検証

BigQueryコンソールで `02_streak_effect.sql` を実行。

### 3. 組み合わせ戦略検証

BigQueryコンソールで `03_combined_strategy.sql` を実行。
「すべての日」カテゴリを含め、日付カテゴリに関係なく有効なパターンを確認。

## 参照テーブル

- `yobun-450512.datamart.machine_stats`: 台番別統計（prev_d2/d3/d5_win_rate など）
- `yobun-450512.scraped_data.events`: イベント情報（date, hole, event）

## ロードマップ

1. [x] 日付カテゴリ別効果検証
2. [x] 連勝/連敗効果検証
3. [x] 組み合わせ戦略検証（すべての日を含む）
4. [x] 検証結果の考察・戦略確定
5. [x] 狙い台出力クエリの完成
