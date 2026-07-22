# Kicho Roadmap

This document tracks the development roadmap of Kicho.

Implemented features, planned work, and long-term ideas must be clearly separated.

---

## Current Status

The following features are currently implemented:

- [x] Project initialization with `kicho init`
- [x] Project building with `kicho build`
- [x] Build cleanup with `kicho clean`
- [x] Command-line help with `--help` and `-h`
- [x] Version output with `--version` and `-v`
- [x] Basic error handling
- [x] Unknown-command handling
- [x] Project detection using `.latexmkrc`
- [x] README documentation
- [x] CLI specification in `SPEC.md`
- [x] Internal design documentation in `DESIGN.md`

---

## v0.1 — Basic CLI and Documentation

Goal: establish a usable command-line interface and a documented project structure.

### Completed

- [x] Implement `init`
- [x] Implement `build`
- [x] Implement `clean`
- [x] Add help output
- [x] Add version output
- [x] Add basic error messages
- [x] Add command dispatch
- [x] Document installation and quick start
- [x] Document the current CLI
- [x] Document the internal architecture

### Remaining

- [ ] Review all documentation for consistency
- [ ] Create or update `AI.md`
- [x] Add basic automated CLI tests
- [x] Verify behavior when required external commands are missing
- [x] Verify behavior outside a Kicho project
- [ ] Decide the versioning and release procedure
- [ ] Tag the first documented release

---

## v0.2 — Diagnostics and Project Validation

Goal: help users diagnose their LaTeX environment and validate project structure.

### `doctor`

- [ ] Design `kicho doctor`
- [ ] Check whether `latexmk` is available
- [ ] Check whether LuaLaTeX is available
- [ ] Check whether Biber is available
- [ ] Report missing external commands clearly
- [ ] Check whether the current directory contains `.latexmkrc`
- [ ] Check whether the configured main TeX file exists
- [ ] Produce a concise diagnostic summary
- [ ] Define exit-status behavior

### `check`

- [ ] Design `kicho check`
- [ ] Validate the current project structure
- [ ] Detect missing source files
- [ ] Detect missing bibliography directories or files
- [ ] Detect invalid build configuration
- [ ] Distinguish warnings from errors
- [ ] Define machine-readable behavior for future automation

### Testing

- [ ] Add tests for successful diagnostics
- [ ] Add tests for missing tools
- [ ] Add tests for malformed projects
- [x] Add tests for exit codes and standard-error output

---

## v0.3 — Document Structure Tools

Goal: support transitions between single-file and multi-file LaTeX projects.

### `split`

- [x] Define marker-based behavior for `kicho split`
- [x] Use explicit markers instead of parsing section commands
- [x] Generate filenames from validated marker names
- [x] Insert `\input` commands safely
- [x] Preserve document order
- [x] Create a backup before modifying source files
- [x] Avoid overwriting existing section files
- [x] Verify that the resulting project still builds
- [x] Preserve marked content line-for-line

### `flatten`

- [x] Define the MVP behavior of `kicho flatten`
- [x] Resolve full-line `\input` commands
- [x] Resolve full-line `\include` commands
- [x] Preserve non-expanded lines
- [x] Collect required bibliography files in `submit`
- [x] Collect required figures in `submit`
- [x] Create a separate submission directory
- [x] Avoid modifying the working project
- [x] Verify that flattened output builds independently

---

## v0.4 — Archiving and Submission Preparation

Goal: support reproducible project snapshots and submission-ready packages.

### `archive`

- [x] Define archive contents
- [x] Include source files
- [x] Include bibliography files
- [x] Include figures
- [x] Include the compiled PDF when available
- [x] Include relevant configuration files
- [x] Exclude temporary build artifacts
- [x] Add version, timestamp, project, and read-only Git metadata
- [x] Define archive naming rules
- [ ] Produce a compressed archive

### `submit`

- [x] Define the MVP scope of `kicho submit`
- [ ] Build the current project before packaging
- [x] Flatten the project when packaging
- [x] Collect submission files
- [x] Validate the generated package
- [ ] Support submission profiles in the future
- [x] Avoid automatic uploading in the initial implementation
- [x] Produce a clear output-directory summary

---

## Future Configuration

The current implementation uses `.latexmkrc` for build configuration and project detection.

Possible future work:

- [ ] Decide whether to introduce `kicho.toml`
- [ ] Make the main TeX document configurable
- [ ] Make the build directory configurable
- [ ] Store project metadata
- [ ] Store archive settings
- [ ] Store flatten settings
- [ ] Store submission profiles
- [ ] Define configuration precedence
- [ ] Add configuration validation
- [ ] Add a configuration migration policy

A dedicated configuration file should only be introduced when Kicho has enough Kicho-specific settings to justify it.

---

## CLI Improvements

- [ ] Support command-specific help such as `kicho build --help`
- [ ] Improve error-message consistency
- [ ] Standardize exit codes
- [ ] Add verbose output
- [ ] Add quiet output
- [ ] Consider colored terminal output
- [ ] Detect whether standard output is connected to a terminal
- [ ] Add shell-completion support
- [ ] Consider `kicho help COMMAND`

---

## Safety and Reliability

- [ ] Prevent accidental overwriting
- [ ] Require backups for destructive transformations
- [ ] Ensure `clean` never deletes source files
- [ ] Ensure generated output stays inside known directories
- [ ] Handle filenames containing spaces
- [ ] Handle interrupted commands safely
- [ ] Test paths containing non-ASCII characters
- [ ] Add dry-run support for file-transforming commands
- [ ] Document destructive behavior explicitly

---

## Compatibility

- [ ] Test with current macOS
- [ ] Test with MacTeX
- [ ] Test with Visual Studio Code and LaTeX Workshop
- [ ] Test direct `latexmk` compatibility
- [ ] Test TeXShop workflows
- [ ] Investigate Linux support
- [ ] Investigate Windows support
- [ ] Define the minimum supported shell environment
- [ ] Define required versions of external tools

---

## Distribution

- [ ] Decide how users should install Kicho
- [ ] Consider adding Kicho to the user's `PATH`
- [ ] Provide an installation script only if justified
- [ ] Consider Homebrew distribution
- [ ] Decide whether shell-script distribution remains sufficient
- [ ] Define upgrade instructions
- [ ] Define uninstall instructions
- [ ] Create release notes

---

## Implementation Evolution

The current implementation is a shell script.

Possible future work:

- [ ] Keep command functions small and independent
- [ ] Separate command dispatch from command implementation
- [ ] Add reusable error and logging functions
- [x] Add a test harness
- [x] Add ShellCheck to the test harness
- [ ] Evaluate shell limitations as features grow
- [ ] Consider another implementation language only when necessary
- [ ] Preserve the existing CLI if the implementation language changes

Potential reasons for migration include:

- complex TOML parsing
- substantial TeX source transformations
- cross-platform distribution
- structured testing
- increasingly complex error handling

---

## Documentation

- [x] Create `README.md`
- [x] Create `SPEC.md`
- [x] Create `DESIGN.md`
- [ ] Create or revise `AI.md`
- [ ] Keep implemented and planned features separate
- [ ] Add command examples as commands are implemented
- [ ] Add troubleshooting documentation
- [ ] Add contribution guidelines if external contributions begin
- [ ] Add release notes
- [ ] Review documentation before each release

---

## Long-Term Ideas

These ideas are not commitments.

- [ ] Journal-specific submission profiles
- [ ] arXiv preparation workflow
- [ ] Project templates for different document types
- [ ] Bibliography validation
- [ ] Missing-reference detection
- [ ] Figure-file validation
- [ ] Reproducible release bundles
- [ ] Project metadata summaries
- [ ] Integration with Git
- [ ] Integration with editors
- [ ] Migration tools for existing LaTeX projects
- [ ] A plugin or extension system

---

## Development Order

The current preferred implementation order is:

```text
documentation consistency
        ↓
automated CLI tests
        ↓
doctor
        ↓
check
        ↓
split
        ↓
flatten
        ↓
archive
        ↓
submit
```

Major new commands should follow this process:

```text
design
   ↓
specification
   ↓
implementation
   ↓
testing
   ↓
documentation
   ↓
release
```
