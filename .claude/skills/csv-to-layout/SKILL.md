---
name: csv-to-layout
description: CSVファイルをヒートマップレイアウトJSON v2.0に変換する
allowed-tools: Bash(node scripts/*), Bash(ls *), Read, Write, Edit, Glob, Grep
argument-hint: <CSVファイルパス> [--hole <店舗名>] [--output <出力先ディレクトリ>]
---

# CSV to Heatmap Layout 変換スキル

CSV ファイルからヒートマップレイアウト JSON (v2.0) を生成する。

## 前提

- CSV フォーマット仕様: `docs/csv-layout-format.md`
- 変換スクリプト: `scripts/parse-layout-csv.js`
- 出力形式: Layout JSON v2.0（`version`, `hole`, `floor`, `grid`, `walls`, `cells`）

## 実行手順

### 1. CSV ファイルの構造を確認

まず CSV の先頭 5-10 行を Read で表示して以下を判断する:

- **1列目の内容**: 行ラベル（`1→`, 空欄等）か、それともデータか → `--skip-col` の値を決定
- **台番号の分布**: 千の位が複数あるか（マルチフロア）、単一か
- **構造物の有無**: 階段、エスカレーター等のキーワードがあるか

### 2. パラメータの決定

`$ARGUMENTS` とCSV内容から以下を決定する:

| パラメータ | 決定方法 |
|-----------|---------|
| 店舗名 (`--hole`) | ユーザー指示、CSVファイル名、`src/config/slorepo-config.js` の正式名称を使用 |
| 出力先 | ユーザー指示。デフォルト: `.temporaly/` |
| フロア分割 | 台番号の千の位が複数グループある場合、ユーザーに確認 |
| `--skip-col` | 1列目が行ラベルなら 1（デフォルト）、データなら 0 |

### 3. 変換の実行

#### シングルフロアの場合

```bash
node scripts/parse-layout-csv.js <CSV> \
  --hole "<店舗名>" --floor <フロア名> \
  --output <出力パス>
```

#### マルチフロアの場合

ALL（全フロア統合）を生成し、各フロアごとに `--machine-filter` + `--trim-cols` で切り出す。

```bash
# ALL
node scripts/parse-layout-csv.js <CSV> --hole "<店舗名>" --floor ALL \
  --output <出力先>/<slug>-all.json

# 各フロア
node scripts/parse-layout-csv.js <CSV> --hole "<店舗名>" --floor 2F \
  --machine-filter 2000-2999 --trim-cols \
  --output <出力先>/<slug>-2f.json
```

出力ファイル名のスラッグは `src/config/heatmap-layouts/storage.js` の `holeToSlug` マッピングを参照:

| 店舗名 | スラッグ |
|--------|---------|
| アイランド秋葉原店 | island-akihabara |
| エスパス秋葉原駅前店 | espace-akihabara |
| ビッグアップル秋葉原店 | bigapple-akihabara |
| 秋葉原UNO | uno-akihabara |
| エスパス上野本館 | espace-ueno |
| 三ノ輪ＵＮＯ | uno-minowa |
| マルハン新宿東宝ビル店 | maruhan-shinjuku |
| マルハン鹿浜店 | maruhan-shikahama |
| ジュラク王子店 | juraku-oji |
| メッセ竹の塚 | messe-takenotsuka |
| ニュークラウン綾瀬店 | newcrown-ayase |
| タイヨーネオ富山店 | taiyoneo-toyama |
| KEIZ富山田中店 | keiz-toyama |

### 4. 出力の検証

- 生成された JSON の `grid` サイズと `cells` 数を確認
- 台番号がフロアごとに正しく分離されているか確認
- 構造物（階段等）が適切な位置にあるか確認

### 5. トラブルシューティング

| 問題 | 対処 |
|------|------|
| ヘッダー行がある | CSV の1行目がヘッダーなら手動削除してから再実行 |
| 台番号が3桁のみ | 台番号範囲は 100-9999 なのでそのまま動作する |
| フロア分割が不要 | `--machine-filter` と `--trim-cols` を省略 |
| 列がずれる | `--skip-col 0` or `--skip-col 2` で調整 |
| 空行が多い | CSV 自体は問題なし（空セルは無視される） |
| 構造物が認識されない | `docs/csv-layout-format.md` のキーワード一覧を確認 |

### 6. GCS アップロード（任意）

生成後、以下の方法で GCS にアップロード:
- **API**: `PUT /api/heatmap/layouts/:hole/:floor` に JSON body を送信
- **エディタ**: `heatmap-editor.html` で新規フロアを作成後、JSON をインポート
