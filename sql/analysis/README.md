# 狙い台分析システム

## 📋 概要

スロット台の高設定予測精度を向上させるための分析システムです。
複数の分析手法を開発・評価し、最終的にはアンサンブル（統合）することで、より堅牢な予測を目指します。

---

## 🗂️ ディレクトリ構造

```
sql/analysis/
├── README.md                           # このファイル
├── ROADMAP.md                          # 開発ロードマップ
├── simple_prediction/                  # シンプル狙い台予測（個別戦略の検証用）
│   ├── README.md
│   ├── 01_day_category_effect.sql      # 日付カテゴリ別効果検証
│   └── 02_recent_winrate_effect.sql    # 直近勝率の効果検証
├── strategy_matching/                  # Phase 1: 戦略マッチング（完成・運用中）
│   ├── README.md
│   ├── recommendation_output.sql       # 狙い台一覧出力
│   ├── recommendation_evaluation.sql   # 評価クエリ
│   └── ...
├── time_series/                        # Phase 2: 時系列パターン分析（計画中）
│   └── README.md
├── correlation/                        # Phase 3: 台番相関分析（計画中）
│   └── README.md
├── machine_learning/                   # Phase 4: 機械学習予測（計画中）
│   └── README.md
└── ensemble/                           # Phase 5: アンサンブル統合（計画中）
    └── README.md
```

---

## 📊 分析手法一覧

| 手法 | フェーズ | ステータス | 概要 |
|------|----------|-----------|------|
| [シンプル狙い台予測](./simple_prediction/README.md) | - | 🔬 検証中 | 個別戦略の効果検証（LINE告知/特日/直近勝率） |
| [戦略マッチング](./strategy_matching/README.md) | Phase 1 | ✅ 運用中 | 事前定義した戦略条件に基づく予測 |
| [時系列パターン分析](./time_series/README.md) | Phase 2 | 📅 計画中 | 周期性・トレンド・リバウンドの検出 |
| [台番相関分析](./correlation/README.md) | Phase 3 | 📅 計画中 | 台同士の相関・ローテーション検出 |
| [機械学習予測](./machine_learning/README.md) | Phase 4 | 📅 計画中 | 特徴量エンジニアリング + ML予測 |
| [アンサンブル統合](./ensemble/README.md) | Phase 5 | 📅 計画中 | 複数手法の統合 |

---

## 🚀 クイックスタート

### 現在利用可能な機能

#### 狙い台一覧の取得（戦略マッチング）

1. BigQuery Connectorで `strategy_matching/recommendation_output.sql` をスプレッドシートに接続
2. フィルタ機能で `priority_rank >= 3` など必要な条件を設定
3. 優先度ランクが高い台を狙う

詳細: [戦略マッチング手法](./strategy_matching/README.md)

---

## 📊 各手法の比較

| 手法 | 実装難易度 | データ要件 | 解釈性 | 補完性 |
|------|-----------|-----------|--------|--------|
| 戦略マッチング | ★★☆☆☆ | 中（28日） | 高い | - |
| 時系列パターン | ★★★☆☆ | 中（30日） | 高い | ◎ |
| 台番相関 | ★★★☆☆ | 高（60日） | 中程度 | ◎ |
| 機械学習 | ★★★★☆ | 高（90日） | 低い | ○ |
| アンサンブル | ★★★★★ | 高 | 中程度 | ◎ |

---

## 🎯 成功指標

各フェーズの成功は以下の指標で評価します：

| 指標 | 目標値 | 説明 |
|------|--------|------|
| **勝率** | 55%以上 | TOP1〜TOP3の平均勝率 |
| **機械割** | 103%以上 | TOP1〜TOP3の平均機械割 |
| **既存手法との差** | +2%以上 | 機械割の改善幅 |

---

## 📝 データマート

分析クエリは `yobun-450512.datamart.machine_stats` テーブルを参照します。

### 主要カラム

| カラム | 説明 |
|--------|------|
| `target_date` | 集計日 |
| `hole` | 店舗名 |
| `machine_number` | 台番 |
| `machine` | 機種名 |
| `d1_diff`, `d1_game`, `d1_payout_rate` | 当日データ |
| `prev_d*_*` | 当日を含まない過去N日間のデータ |

詳細は [データマート生成クエリ](../datamart_machine_stats.sql) を参照。

---

## 🔄 更新履歴

| 日付 | 変更内容 |
|------|----------|
| 2026-02-01 | シンプル狙い台予測を追加（個別戦略の効果検証用） |
| 2026-01-14 | ディレクトリ構造を再編成、各手法を分離 |
| 2026-01-13 | 戦略マッチング手法を複数店舗・機種対応に拡張 |

---

## 📚 関連ドキュメント

- [開発ロードマップ](./ROADMAP.md)
- [シンプル狙い台予測](./simple_prediction/README.md)
- [戦略マッチング手法](./strategy_matching/README.md)
- [時系列パターン分析](./time_series/README.md)
- [台番相関分析](./correlation/README.md)
- [機械学習予測](./machine_learning/README.md)
- [アンサンブル統合](./ensemble/README.md)
- [データマート生成クエリ](../datamart_machine_stats.sql)
