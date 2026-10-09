# Changelog

All notable user-visible changes to Kicho are documented in this file.

## [Unreleased]

### Added

- Configure main/build paths through literal `kicho.conf`, environment variables,
  and global `--main` / `--build-dir` options
- Summarize unresolved TeX citations/references with `check --log` and `build --strict`
- Diagnose optional Python 3.9+ and ZIP capabilities in `doctor`
- Record SHA-256 file hashes and installed TeX tool versions in schema-2 manifests

- Source file/line diagnostics and `check --json` structured output
- `submit --build` to refresh PDFs, compiled bibliographies, and recorder files
- Warnings when known inputs are newer than a copied submission PDF or BBL
- Manage the paragraphids package and literal IDs with `paraids install/new/find/check`
- Disable paragraph IDs, red notes, and showkeys in submission sources; rebuild
  marked standard-submission PDFs and omit the editorial package
- Preserve local style files, including the review package, in archives

- Preserve project-local dependencies in archives and submission packages,
  including inputs outside conventional directories and inline input references
- Ignore comments and literal examples when detecting bibliography usage
- Avoid treating inline verbatim examples as environment openings

### Changed

- Separate ordered source traversal, project paths, TeX log diagnostics, arXiv
  packaging, and provenance from individual command implementations
- Reuse one deduplicated dependency collector for copying and freshness checks
- Check the Bash syntax of each shell file individually in the test harness

### Fixed

- Preserve referenced figures, recorded data, other files, and populated caches
  during cleaning; prune only empty generated directories after latexmk
- Collect multiline literal dependencies and restore graphics search paths after
  explicit groups and environments, including groups spanning input files
- Reject directory symlinks in source and recorder references and arXiv figures
- Ignore comments and literal examples when extracting arXiv metadata
- Reject path overrides whose outer whitespace cannot survive configuration storage

- Keep explicitly referenced hidden files in arXiv ZIPs while excluding unrelated
  hidden figure files; compile extracted ZIPs in real-template smoke tests
- Process supported static commands in source order, including repeated inputs
  under different graphicspath settings
- Refuse cleaning generated directories containing authored TeX/bibliography/style files
- Clean submission staging on failures and handled HUP/INT/TERM signals

- Resolve literal graphicspath lists and report input/include cycles in `check`
- Preserve nested project-local styles/classes and compiler-recorded inputs
- Keep generated archive/submission copies out of paragraph-ID directory scans
- Stage complete archives before publication and clean up after failures and signals
- Reject dependency copies through symlinks in export destinations
- Preserve known verbatim and listing environments during flattening and submission
- Check every literal file reference on a line and retain escaped percent signs
- Reject symbolic-link flatten output directories and dangling destination links
- Warn when static checks find missing or invalid dependencies in archived sources

## [0.2.0-alpha.3] - 2026-08-26

### Fixed

- Roll back files created by `split` when a later write fails, and avoid
  publishing an arXiv package before generated root metadata is saved
- Preserve AMS math fonts in the English template so inline and display
  mathematics work inside the `amsart` abstract

### Changed

- Separate shared metadata and path predicates from command implementations
- Share the shell-test runner and assertions across test files
- Add real English and Japanese LuaLaTeX template smoke builds to CI
- Consolidate roadmap and architectural review documentation into `TODO.md`
  and `REVIEW.md`

### Added

- Allow `kicho split FILE` to divide an existing project-local TeX file into
  additional section files
- Add `kicho submit --arxiv` for a flattened source ZIP containing `main.bbl`
  instead of `.bib` files, plus a reusable metadata worksheet for manual review
- Add a project-local LuaTeX font-cache fallback for Kicho, generated
  `.latexmkrc` files, and cache-writability diagnostics in `kicho doctor`
- Add `kicho submit --output DIRECTORY` for preserving earlier submission
  packages and preparing revisions without overwriting them

## [0.2.0-alpha.2] - 2026-07-30

### Fixed

- Prevent LaTeX Workshop save-triggered builds from bypassing `latexmk` because
  of a `% !TEX program` magic comment
- Use a relative root filename in the bundled LaTeX Workshop recipe so projects
  under iCloud Drive paths containing spaces or `~` build correctly
- Point the LaTeX Workshop PDF viewer at the expected `build/main.pdf` output
- Report an unknown `init` template clearly even when the project name is omitted

## [0.2.0-alpha.1] - 2026-07-22

### Added

- Command metadata for summaries, usage, examples, aliases, and requirements
- `kicho help COMMAND` and `kicho COMMAND --help`
- English and Japanese project templates
- Environment diagnostics with `kicho doctor`
- Static project validation with `kicho check`
- Marker-based source splitting with `kicho split`
- Recursive source flattening with `kicho flatten`
- Project snapshots with `kicho archive`
- Local submission packages with `kicho submit`
- ShellCheck, syntax, CLI, diagnostic, archive, and workflow tests
- macOS GitHub Actions coverage using the system Bash 3.2

### Changed

- Centralized project and `latexmk` precondition checks in the command loader
- Standardized command help, unsupported-argument errors, exit behavior, and
  overwrite protection
- Expanded documentation to describe the implemented workflow

## [0.1.0]

### Added

- Project initialization with `init`
- LaTeX builds with `build`
- Generated-file cleanup with `clean`
- Initial README, specification, design, and roadmap
