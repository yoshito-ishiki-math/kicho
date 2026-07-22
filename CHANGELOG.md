# Changelog

All notable user-visible changes to Kicho are documented in this file.

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
