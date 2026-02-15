---
name: playground
description: "Use proactively when testing, experimenting, prototyping, or doing proof-of-concept work. Reminds that .playground/ is available as a git-ignored sandbox. Triggers on: test, experiment, POC, proof of concept, prototype, try, sandbox, scratch, spike, verify, validate, playground."
---

# `.playground/` サンドボックスの活用

## 概要

`.playground/` は **git 管理外のサンドボックスディレクトリ**。テスト・実験・POC・プロトタイプ・スクラッチコードに自由に利用できる。

## 仕組み

- `.gitignore` に `.playground/*` が記載されており、中のファイルはすべて git 管理外
- `.playground/.gitkeep` によりディレクトリ自体は git で管理されている（常に存在する）
- コミットに含まれないため、何を置いても本番コードに影響しない

## 使いどころ

| 用途 | 例 |
|------|-----|
| 一時的なスクリプト | 動作確認用の小さなスクリプトを書いて実行 |
| 動作検証 | 特定の関数やモジュールの挙動を単体で確認 |
| ライブラリの試用 | 新しいライブラリの API を試す |
| POC・プロトタイプ | 設計案の実現可能性を小さく検証 |
| デバッグ用コード | 再現コードや調査用スクリプトの配置 |
| スパイク | 技術的な不確実性を解消するための実験 |

## 注意事項

- `.playground/` 内のファイルは永続化されない前提で使うこと（他の開発者の環境には共有されない）
- 検証が完了し本番に採用する場合は、適切なディレクトリに移動してコミットすること
