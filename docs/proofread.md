# 校正用の赤字と著者承認

`proofread` は修正案をID付きの赤字で示し、著者承認後にKichoから通常本文へ
確定する機能です。段落IDや余白の指摘注記とは別に、本文の追加・削除・置換を
記録します。Python 3.9以上と、原稿を組版できるLaTeX環境を使用します。

## 1. 原稿に導入する

原稿のルートディレクトリで実行します。別の場所からは各コマンドに
`--root MyPaper` を指定できます。

```sh
kicho proofread install
```

原稿のプリアンブルに追加します。

```tex
\usepackage{kichoproof}
```

導入処理は原稿を書き換えません。同一内容のパッケージはそのまま使い、
既存の異なるパッケージは上書きせず停止します。

## 2. 修正案を入力する

```sh
kicho proofread new --kind add --new '追加する文章'
kicho proofread new --kind delete --old '削除する文章'
kicho proofread new --kind replace --old '元の文章' --new '修正後の文章'
```

`new` は新しいIDを持つLaTeXコマンドを出力します。出力を確認し、原稿の
該当箇所へ貼り付けます。原稿への自動挿入は行いません。構文は次のとおりです。

```tex
\kichoadd{r-0123456789ab}{追加する文章}
\kichodelete{r-123456789abc}{削除する文章}
\kichoreplace{r-23456789abcd}{元の文章}{修正後の文章}
```

各修正には別のIDを使います。`kicho build` でPDFを更新すると、修正箇所が
赤字で表示され、IDと削除・置換の区別から対象を特定できます。

## 3. 確認し、著者承認を記録する

```sh
kicho proofread list
kicho proofread check
```

`list` はファイル名・行番号・ID・修正の種類を表示します。著者承認を得た箇所の
IDを指定します。複数IDも指定できます。

```sh
kicho proofread approve r-23456789abcd --author '著者名'
kicho build
```

追加は追加文を残し、削除は対象を除き、置換は修正後の文を残します。
書式の有効範囲や制御綴の区切りを保つため、確定した本文の波括弧は残し、
削除箇所には空の `{}` を残します。
承認済みの箇所は通常本文になり、他の修正案は赤字のまま残ります。
全件が承認された場合だけ、次のコマンドを使用します。

```sh
kicho proofread approve --all --author '著者名'
kicho build
```

承認時には変更前の原稿、変更前後のSHA-256、修正内容、著者名、UTC時刻を
`archives/proofread/<操作ごとのディレクトリ>/` に保存します。
`--author` は入力された承認者名の記録で、本人認証ではありません。
ビルド成功や時間経過から承認を推測することはありません。
PDFは承認コマンドだけでは更新されないため、承認後に再ビルドしてください。

## 4. 提出用のファイルを作る

`submit` と `submit --arxiv` は未承認・不正な修正を含む提出用ソースを拒否します。
すべて承認済みなら、提出用コピーで不要な校正パッケージを除きます。
通常の提出では校正情報を含む原稿からPDFを再ビルドし、古い赤字付きPDFの
混入を防ぎます。`archive` は未承認の赤字を含む作業状態をそのまま保存します。

## 対応範囲

明示的に書かれたUTF-8の修正コマンドを対象とします。入れ子の波括弧、段落、
インライン数式に対応します。別行数式は環境全体を一つの修正の中に置き、
環境の開始・終了をまたぐ修正は避けてください。修正コマンドの入れ子、
verbatimを含む修正文、独自マクロによる修正コマンドの生成は対象外です。
TeXのマクロ展開や条件分岐は評価しません。

コメントと既知のverbatim・listing環境内の例示は検査から除きます。
ディレクトリの走査ではビルド先、`archives/`、投稿用ディレクトリ、および
Kichoのmanifestで識別される提出物を除きます。その他の旧稿を含まないよう、
現在の原稿だけを含むルートを指定してください。新ID発行ではコメント内のIDも
予約済みとします。完全なCLI仕様は [SPEC.md](../SPEC.md#proofread) を参照してください。

## English quick reference

Install with `kicho proofread install`, load `kichoproof` in the preamble,
and paste a snippet printed by `kicho proofread new --kind replace --old 'Old'
--new 'New'`. Build to review its red correction and ID. Use `list` and `check`
to locate and validate corrections. After author approval, run
`kicho proofread approve ID --author 'Author Name'` and rebuild.
Approval keeps accepted text and saves original source plus audit metadata;
it does not authenticate the name. Pending corrections block both submission
modes. The helper operates on literal source and does not expand TeX macros.
