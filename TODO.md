- [ ] --english
- [ ] --japanese
- [ ] --blog
- [ ] Git初期化
- [ ] VS Code起動
- [ ] arXivテンプレート
## Rename

- [ ] Rename the project from `newpaper` to `Kicho`.
- [ ] Rename the CLI command from `newpaper` to `kicho`.
- [ ] Update the README and documentation to reflect the new name.
- [ ] Explain that the name **Kicho** comes from the Japanese word **記帳** ("keeping a written record").

## Workflow

- [ ] Implement `kicho init`.
- [ ] Implement `kicho build`.
- [ ] Implement `kicho clean`.
- [ ] Implement `kicho archive`.

## Source organization

- [ ] Implement `kicho split` to split a single-file manuscript into section-based files.
- [ ] Implement `kicho flatten` to recursively expand local `\input` files into a single TeX source.
- [ ] Document the design philosophy that **split** and **flatten** are complementary workflow tools rather than exact inverse operations.
- [ ] Keep both single-file and multi-file workflows as first-class citizens.

## Template

- [ ] Use `amsart` as the default document class.
- [ ] Include a standard mathematical paper template (`packages.tex`, `macros.tex`, `theorem.tex`).
- [ ] Provide compatibility macros for legacy notation (e.g. `\yonn`, `\nn`, etc.).
- [ ] Include AMS metadata (`\subjclass`, `\keywords`, `\thanks`, `\address`, `\email`) in the default template.
