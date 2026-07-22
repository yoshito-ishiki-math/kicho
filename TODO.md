# Kicho Roadmap

This document tracks implemented work and remaining priorities. Completed
features are retained only when they clarify release scope.

---

## Current Status

Kicho currently implements:

- [x] English and Japanese project initialization with `init`
- [x] `build` and `clean` through `latexmk`
- [x] environment diagnostics with `doctor`
- [x] static project validation with `check`
- [x] marker-based `split`
- [x] recursive full-line `flatten`
- [x] project snapshots with `archive`
- [x] local submission packages with `submit`
- [x] command metadata and `kicho help COMMAND`
- [x] `kicho COMMAND --help` and `kicho COMMAND -h`
- [x] ShellCheck, Bash syntax, and integration tests
- [x] macOS GitHub Actions using the system Bash 3.2

---

## v0.1.0 — Basic CLI

- [x] Implement `init`, `build`, and `clean`
- [x] Add global help and version output
- [x] Add project and `latexmk` precondition checks
- [x] Establish README, specification, design, and roadmap documents
- [x] Add the initial CLI test harness

---

## v0.2.0-alpha.1 — Workflow and Diagnostics

The next version is `0.2.0-alpha.1`. The prerelease label is appropriate while
the new macOS CI workflow and the `check` MVP receive real-project use.

### Completed for the prerelease

- [x] Add command objects through optional metadata functions
- [x] Add automatic command-specific help
- [x] Centralize project and `latexmk` requirements
- [x] Add English and Japanese templates
- [x] Implement and document `doctor`
- [x] Test `doctor` success, warnings, required-tool failures, and independence
      from incomplete projects
- [x] Implement the `check` MVP
- [x] Validate `main.tex` and `.latexmkrc`
- [x] Validate literal input, bibliography, and figure references
- [x] Distinguish project warnings from errors
- [x] Implement `split`, `flatten`, `archive`, and `submit`
- [x] Standardize command help, unsupported arguments, and output streams
- [x] Test overwrite protection for generated destinations
- [x] Add ShellCheck to the local test harness
- [x] Add macOS GitHub Actions with `/bin/bash`
- [x] Audit README, SPEC, DESIGN, AI, TODO, and CHANGELOG

### Before promoting to v0.2.0

- [x] Confirm the GitHub Actions workflow passes after push
- [ ] Use the prerelease on representative English and Japanese projects
- [ ] Fix any diagnostics that produce misleading results on real projects
- [ ] Promote the version to `0.2.0`
- [ ] Add the final changelog date and create the annotated release tag

---

## Next Priorities

### Diagnostics

- [ ] Support multiple literal references on one TeX source line
- [ ] Recognize `\graphicspath`
- [ ] Report include cycles in `check`
- [ ] Add an optional machine-readable `check` format
- [ ] Add missing citation and reference diagnostics only if a reliable existing
      TeX tool can provide them

### Archiving and Submission

- [ ] Add an optional compressed archive format
- [ ] Decide whether `submit` should build before packaging
- [ ] Add submission profiles only after concrete journal requirements are known

### Configuration

- [ ] Decide whether Kicho-specific settings justify `kicho.toml`
- [ ] Make the main TeX file configurable
- [ ] Make generated output locations configurable
- [ ] Define configuration precedence, validation, and migration

### CLI

- [ ] Add shell completion generated from command metadata
- [ ] Consider quiet and verbose modes
- [ ] Consider dry-run behavior for file-transforming commands
- [ ] Add aliases only when stable abbreviations are clear

### Compatibility and Distribution

- [ ] Test direct MacTeX, TeXShop, and LaTeX Workshop workflows
- [ ] Investigate Linux support
- [ ] Decide the installation and upgrade mechanism
- [ ] Consider Homebrew distribution
- [ ] Define uninstall instructions

---

## Safety Invariants

- [x] Initialization refuses an existing destination
- [x] `split` validates before writing and creates a backup
- [x] `flatten` and `submit` refuse existing destinations
- [x] `clean` removes only generated build output
- [x] File transformations constrain references to the project
- [x] Tests cover spaces and non-ASCII project paths
- [ ] Handle interrupted multi-file writes transactionally where practical

---

## Long-Term Ideas

These ideas are not commitments:

- journal-specific submission profiles
- arXiv preparation
- additional document templates
- reproducible release bundles
- editor integrations
- migration tools for existing LaTeX projects
- a plugin system
