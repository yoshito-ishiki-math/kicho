# Changelog

All notable user-visible changes to Kicho are documented in this file.

## [Unreleased]

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
