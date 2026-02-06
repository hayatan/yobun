# ヒートマップレイアウト CSV フォーマット仕様

ヒートマップレイアウトの元データとなる CSV ファイルの作成方法。
Google Sheets や Excel で台配置図を作成し、CSV としてエクスポートして使用する。

## 基本ルール

### ファイル形式

- エンコーディング: UTF-8
- 区切り文字: カンマ（`,`）
- 改行: LF または CRLF
- ヘッダー行: **なし**（1行目からグリッドデータ）

### グリッド構造

- 各セルがフロアの1マスに対応する
- 1行目 = フロアの最上行、最終行 = フロアの最下行
- **1列目は行ラベル用**（変換時に自動スキップ）。空欄、`1→`、`A` 等、任意の値を入れてよい
- 2列目以降がレイアウトデータ

> `--skip-col` オプションでスキップ列数を変更可能（デフォルト: 1）

### セルの値

| セル内容 | 変換結果 | 例 |
|---------|---------|-----|
| 3-4桁の数字 | 台番号（machine） | `2124`, `3015`, `401` |
| 構造物キーワード | 構造物（structure） | `階段`, `エスカレーター`, `カウンター` |
| その他のテキスト | ラベル（label） | `☆`, `通路`, `A列` |
| 空欄 | 無視（空きスペース） | |

### 構造物キーワード一覧

| キーワード | 種別 (subtype) |
|-----------|---------------|
| `階段` | stairs |
| `エスカレーター`, `ＥＳ`, `ES` | escalator |
| `カウンター`, `精算機`, `POS`, `MC` | counter |
| `ロッカー` | locker |
| `自販機` | vending |
| `柱` | pillar |
| `棚` | shelf |
| `WC`, `トイレ` | restroom |
| `入口`, `出口` | entrance |
| `ATM` | other |

キーワードは部分一致で判定される（例: `大階段` も `stairs` として認識）。

## マルチフロア配置

### 台番号によるフロア識別

台番号の千の位でフロアを識別するのが一般的なパターン:

- 1000番台 → 1F
- 2000番台 → 2F
- 3000番台 → 3F
- 4000番台 → 4F

### 同一シートに複数フロアを配置する場合

フロアを横方向に並べる。空列で区切りを入れると見やすい。

```
,2001,,2010,2005,,,,3001,,3010,3005,
,2002,,2009,2006,,,,3002,,3009,3006,
,2003,,2008,2007,,,,3003,,3008,3007,
,2004,,階段,階段,,,,3004,,階段,階段,
```

変換時は `--machine-filter` と `--trim-cols` でフロアごとに切り出す:

```bash
# 2F のみ
node scripts/parse-layout-csv.js data.csv --hole "店舗名" --floor 2F \
  --machine-filter 2000-2999 --trim-cols --output out-2f.json

# 3F のみ
node scripts/parse-layout-csv.js data.csv --hole "店舗名" --floor 3F \
  --machine-filter 3000-3999 --trim-cols --output out-3f.json
```

### シングルフロアの場合

フロアが1つだけなら、フィルタなしでそのまま変換:

```bash
node scripts/parse-layout-csv.js data.csv --hole "店舗名" --floor 1F --output out.json
```

## 作成のコツ

1. **Google Sheets 推奨**: セルの幅を均等にし、グリッド感を出す
2. **空列で区切る**: フロア間に1列以上の空列を入れると視認性が上がる
3. **行ラベルは1列目に**: `1→`, `2→` 等の行番号は1列目に入れる（自動スキップ）
4. **台番号は数字のみ**: "No." やプレフィックスは不要。3-4桁の数字だけを入力
5. **構造物はキーワードで**: 上記キーワード一覧に含まれる文字列を入れると自動認識
6. **空行も保持**: 通路などの空きスペースは空欄のまま。行の高さがグリッドの行数に直結する

## 変換コマンド

```bash
# 基本（フィルタなし、stdoutに出力）
node scripts/parse-layout-csv.js data.csv --hole "エスパス秋葉原駅前店" --floor ALL

# ファイルに出力
node scripts/parse-layout-csv.js data.csv --hole "エスパス秋葉原駅前店" --floor ALL \
  --output ./output/layout-all.json

# 台番号フィルタ + 列トリム（フロア切り出し）
node scripts/parse-layout-csv.js data.csv --hole "エスパス秋葉原駅前店" --floor 2F \
  --machine-filter 2000-2999 --trim-cols --output ./output/layout-2f.json

# 統計のみ確認（ファイル出力なし）
node scripts/parse-layout-csv.js data.csv --hole "エスパス秋葉原駅前店" --floor ALL --dry-run

# 行ラベル列がない場合
node scripts/parse-layout-csv.js data.csv --hole "店舗名" --floor 1F --skip-col 0
```

## 出力フォーマット

Layout JSON v2.0:

```json
{
  "version": "2.0",
  "hole": "エスパス秋葉原駅前店",
  "floor": "2F",
  "updated": "2026-02-07",
  "description": "CSV「data.csv」から自動生成（2F）",
  "grid": { "rows": 64, "cols": 6 },
  "walls": [],
  "cells": [
    { "row": 0, "col": 0, "type": "machine", "number": 2124 },
    { "row": 0, "col": 3, "type": "structure", "subtype": "stairs", "label": "階段" },
    { "row": 7, "col": 0, "type": "label", "text": "☆" }
  ]
}
```
