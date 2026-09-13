# Kicho

[English](README.md) | 日本語

Kichoは、LaTeXによる研究プロジェクトのワークフローを管理するコマンドラインツールです。

標準的なLaTeXの作業環境との互換性を保ちながら、プロジェクトの作成から学術誌への投稿準備まで、数学論文の執筆全体を支援することを目指しています。

現在は、プロジェクトの初期化、ビルド、生成ファイルの削除、環境診断、プロジェクトの検査、ソースの分割・統合、スナップショットの保存、ローカルでの投稿用パッケージ作成に対応しています。

---

## 機能

### 実装済み

- LaTeX研究プロジェクトの新規作成
- 英語・日本語の組み込み論文テンプレートの選択
- `latexmk`によるビルド
- ビルドで生成されたファイルの削除
- `doctor`によるローカル環境の診断
- `check`によるプロジェクトのファイルと参照先の検査
- `archive`によるソース・PDF・メタデータのスナップショット保存
- `split`による、明示的なマーカーを付けたソースブロックの分割
- `flatten`による、行全体を占める`\input`と`\include`コマンドの展開
- `submit`によるローカルの投稿用パッケージ作成
- `submit --arxiv`によるarXiv投稿用ソースZIPとメタデータ記入用ファイルの作成
- `help COMMAND`または`COMMAND --help`によるコマンド別ヘルプの表示
- `--help`による全体のヘルプ表示
- `--version`によるバージョン情報の表示

### 今後の予定

- TeXの構文をより詳しく考慮したソース変換
- 投稿先に応じた設定プロファイル
- プロジェクト管理用の補助機能

---

## インストール

```bash
git clone https://github.com/yoshito-ishiki-math/kicho.git
cd kicho

chmod +x bin/kicho
```

---

## クイックスタート

新しいプロジェクトを作成します。

```bash
./bin/kicho init MyPaper
```

日本語のプロジェクトには、`jlreq`、LuaLaTeX-ja、およびTeX Liveに含まれる原ノ味フォントを使用するLuaLaTeXテンプレートを選べます。

```bash
./bin/kicho init --template japanese MyJapanesePaper
```

作成したプロジェクトのディレクトリに移動します。

```bash
cd MyPaper
```

プロジェクトをビルドします。

```bash
../bin/kicho build
```

生成されたファイルを削除します。

```bash
../bin/kicho clean
```

インストール済みのツールを診断し、ビルドせずにプロジェクトを検査します。

```bash
../bin/kicho doctor
../bin/kicho check
```

ソース、コンパイル済みPDF、プロジェクトのメタデータをスナップショットとして保存します。

```bash
../bin/kicho archive
```

arXivへのアップロード用ZIPを作成します。先にビルドして、`build/main.bbl`を最新にしておきます。

```bash
../bin/kicho build
../bin/kicho submit --arxiv
```

文献を使用する原稿では、アップロード用ZIPに`.bib`ファイルを含めず、`main.bbl`を含めます。
また、プロジェクト直下に、確認・再利用のための`arxiv-metadata.txt`の草稿を作成します。
Kicho自身はアップロードを行いません。

以前のパッケージを残す場合や改訂版を準備する場合は、プロジェクト内の別の出力先を指定します。

```bash
../bin/kicho submit --arxiv --output submissions/revision-2
```

出力先のディレクトリがすでに存在する場合、Kichoは処理を拒否します。強制的に上書きするオプションはありません。

利用可能なコマンドを表示します。

```bash
../bin/kicho --help
```

---

## テスト

macOSでは、開発用のシェルコード検査ツールをインストールします。

```bash
brew install shellcheck
```

リポジトリのルートディレクトリで、コード検査・構文検査・統合テストをまとめて実行します。

```bash
bash tests/run.sh
```

pushとプルリクエスト時にも、macOS 14のシステム標準`/bin/bash`で同じテストを実行し、Bash 3.2との互換性を確認します。

---

## VS CodeとiCloud Drive

生成されるワークスペース設定では、LaTeX Workshopが手動ビルドと保存時の自動ビルドの両方で`latexmk`を使用します。
TeXプログラムを指定するマジックコメントを無効にし、相対ファイル名`%DOCFILE_EXT%`を渡します。これにより、空白や`~`を含むiCloud Driveの絶対パスをLuaLaTeXに直接渡すことを避けています。

PDFビューアーは`build/main.pdf`を開く設定です。Kichoはプロジェクト直下には`main.pdf`を生成しません。

`TEXMFVAR`が明示的に設定されていない場合、LuaTeXのフォントキャッシュは`build/texmf-var/`に保存されます。
これは、権限が制限されたシェルやエージェントの実行環境で、フォントキャッシュへの書き込みが失敗する問題を避けるためです。
この設定は、`kicho build`、直接実行する`latexmk`、生成されたLaTeX Workshop設定で共通です。
`kicho doctor`でキャッシュの書き込み可否を確認できます。明示的に設定済みの`TEXMFVAR`は維持されます。

コンパイルエンジンは`.latexmkrc`で指定してください。`main.tex`には、次のような行を追加しないでください。

```tex
% !TEX program = lualatex
```

古いプロジェクトでエンジン選択の問題が起きる場合は、マジックコメントを削除し、新しく生成したKichoプロジェクトのワークスペース設定を使用してください。

---

## 生成されるプロジェクト構成

```text
MyPaper/
├── main.tex
├── preamble/
├── sections/
├── bib/
├── figures/
├── build/
└── .latexmkrc
```

---

## ワークフロー

Kichoは、次の作業の流れを想定しています。

```text
init
 ↓
write
 ↓
build
 ↓
split
 ↓
flatten
 ↓
archive
 ↓
submit
```

現在のリリースでは、基本的なプロジェクト操作、スナップショット保存、マーカーによる分割、安全性を考慮したソース統合、ローカルでの投稿用パッケージ作成を実装しています。

---

## 設計思想

Kichoは、LaTeXテンプレートの提供にとどまらず、`latexmk`、LuaLaTeX、Biberなどの標準的なツールを活用して、再現可能で軽量な数学論文の執筆環境を提供することを目指しています。

既存のツールを連携させ、一貫したプロジェクトのワークフローを構成します。

---

## ライセンス

MIT License
