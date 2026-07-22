# Kicho Design

This document describes the internal design, architecture, and development principles of Kicho.

The README introduces Kicho to users.

The specification defines the command-line interface and user-visible behavior.

This document explains how Kicho is structured internally and why those design choices are used.

---

## Design Goals

Kicho is designed as a lightweight workflow manager for LaTeX research projects.

Its primary goals are:

- support the lifecycle of a mathematical paper
- remain compatible with standard LaTeX tools
- keep simple projects simple
- avoid unnecessary project-specific machinery
- provide reproducible commands for common workflows
- remain understandable enough to maintain without a large framework

Kicho should coordinate existing tools rather than replace them.

---

## Workflow Model

Kicho is organized around the lifecycle of a research paper.

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

Not every project must use every stage.

In particular, Kicho should not force a multi-file document structure on small papers.

A user may write a complete paper in `main.tex` and only split the document when it becomes useful.

---

## Command Architecture

Kicho uses a subcommand-oriented command-line interface.

```text
kicho <command> [arguments] [options]
```

Examples:

```bash
kicho init MyPaper
kicho build
kicho clean
```

Each major user operation should normally correspond to one subcommand.

Global options should be limited to Kicho-wide behavior such as:

```bash
kicho --help
kicho --version
```

This design is intended to remain stable as new commands are introduced.

### Command Metadata Protocol

Each command is represented by a required implementation function and a set of
optional metadata functions. For a command named `build`, the protocol is:

```text
kicho_command_build                    required implementation
kicho_command_build_summary            optional summary
kicho_command_build_usage              optional usage text
kicho_command_build_examples           optional examples
kicho_command_build_aliases            optional aliases
kicho_command_build_requires_project   optional project requirement
kicho_command_build_requires_latexmk   optional latexmk requirement
```

The loader queries these functions through their naming convention. This keeps
command files independent while allowing common behavior such as help and
precondition checks to remain in the loader.

Metadata functions are optional. Missing descriptive metadata produces either
no output or a minimal default. Missing requirement metadata means that the
requirement does not apply.

Requirement functions use shell status conventions:

```text
return 0   requirement applies
return 1   requirement does not apply
```

Aliases are whitespace-separated command names printed by the aliases function.
They must use the same naming rules as commands and must not conflict with a
command, another alias, or a reserved command name.

The loader performs command execution in this order:

```text
resolve command or alias
        ↓
query command metadata
        ↓
check shared requirements
        ↓
run the command implementation
```

Commands remain responsible for their unique work. The loader is responsible
for discovery, metadata access, shared validation, and dispatch.

---

## Current Repository Structure

The Kicho repository currently uses a simple structure similar to:

```text
kicho/
├── bin/
│   └── kicho
├── templates/
├── README.md
├── SPEC.md
├── DESIGN.md
├── TODO.md
├── AI.md
└── LICENSE
```

### `bin/`

Contains the executable command-line interface.

The current implementation is centered on:

```text
bin/kicho
```

This script is responsible for:

- parsing commands
- validating arguments
- displaying help and version information
- reporting errors
- dispatching subcommands
- invoking external tools such as `latexmk`

### `templates/`

Contains files copied by:

```bash
kicho init PROJECT
```

The template defines the initial structure of a Kicho project.

Kicho currently provides two built-in paper templates:

```text
templates/english-paper/    amsart, English
templates/japanese-paper/   jlreq, LuaLaTeX-ja, Japanese
```

`kicho init PROJECT` selects the English template for backward compatibility.
`kicho init --template japanese PROJECT` selects the Japanese template. Template
selection belongs to `init`; build behavior remains owned by each template's
`.latexmkrc`.

Documentation files belong to the repository itself and must not be copied into every generated paper project unless there is a specific reason.

---

## Generated Project Structure

A newly created Kicho project currently has a structure similar to:

```text
PROJECT/
├── main.tex
├── preamble/
├── sections/
├── bib/
├── figures/
├── build/
└── .latexmkrc
```

### `main.tex`

The default main document.

The current template assumes `main.tex`, but the main document should become configurable in a future release.

### `preamble/`

Contains reusable preamble fragments or local style definitions.

The directory may remain empty in simple projects.

### `sections/`

Contains split document sections when multi-file organization becomes useful.

Kicho should not require users to move content into this directory immediately.

### `bib/`

Contains bibliography databases and related files.

### `figures/`

Contains figures, diagrams, and other visual assets.

### `build/`

Contains generated compilation files.

This directory is disposable and may be deleted by:

```bash
kicho clean
```

### `.latexmkrc`

Contains the project's LaTeX build configuration.

In the current design, `.latexmkrc` is both:

- the build configuration used by `latexmk`
- the minimal marker used to identify a Kicho project

This is intentionally simple and may change later.

---

## Build Architecture

Kicho delegates compilation to the standard LaTeX toolchain.

```text
kicho build
    ↓
latexmk
    ↓
.latexmkrc
    ↓
LuaLaTeX
    ↓
Biber
```

Kicho should not directly reproduce or override configuration already expressed in `.latexmkrc`.

The build command should remain a thin coordination layer.

This provides several benefits:

- users can still run `latexmk` directly
- editor integrations remain usable
- Kicho does not become a custom build system
- the project remains compatible with ordinary LaTeX environments
- build behavior is inspectable outside Kicho

---

## Clean Architecture

The clean command currently performs two operations:

```text
latexmk -C
```

followed by removal of:

```text
build/
```

The clean command must only remove generated files.

It must not remove:

- source files
- bibliography databases
- figures
- preamble files
- project configuration
- manually created research notes

Generated and source files should remain clearly separated.

---

## Project Detection

The current implementation considers a directory to be a Kicho project when it contains:

```text
.latexmkrc
```

This is a pragmatic temporary rule.

It avoids introducing configuration machinery before Kicho needs it.

However, `.latexmkrc` is fundamentally a LaTeX build configuration file, not a Kicho metadata file.

A future release may introduce:

```text
kicho.toml
```

A dedicated configuration file could explicitly identify a Kicho project and store information such as:

```toml
[project]
main = "main.tex"

[build]
directory = "build"

[archive]
directory = "archive"
```

The configuration format must not be introduced until Kicho has settings that justify it.

---

## Configuration Principles

Kicho should avoid duplicating configuration owned by existing tools.

Examples:

- LuaLaTeX options belong in `.latexmkrc`
- bibliography settings belong in LaTeX or Biber configuration
- editor-specific settings belong in the editor
- Kicho workflow settings may eventually belong in `kicho.toml`

A Kicho-specific setting should only be added when it describes behavior that is genuinely owned by Kicho.

Possible future Kicho settings include:

- main TeX file
- project name
- archive destination
- flatten behavior
- submission profile
- ignored files
- generated package contents

---

## Single-File-First Principle

Kicho follows a single-file-first philosophy.

A new project should be usable immediately with:

```text
main.tex
```

Users should not be forced to begin with many files or directories.

The `sections/` directory exists as an option, not as a requirement.

The future `split` command should help users transition from a large single file to a multi-file structure when needed.

The future `flatten` command should reverse that structure for journal submission or portability.

---

## External Tool Policy

Kicho may rely on standard external tools when they already solve the relevant problem well.

Current dependency:

- `latexmk`

Expected LaTeX toolchain:

- LuaLaTeX
- Biber

Before invoking an external tool, Kicho should check that it is available and provide a clear error if it is missing.

Kicho should preserve the exit status of underlying tools where practical.

---

## Error-Handling Design

Errors should be:

- concise
- actionable
- written to standard error
- free of unnecessary implementation details

Preferred style:

```text
Error: latexmk is not installed or is not available through PATH.
```

When usage is relevant, Kicho should suggest:

```text
Run 'kicho --help' for usage.
```

Commands should fail early before modifying files whenever possible.

---

## File-Safety Principles

Commands that modify files must follow conservative behavior.

Kicho should:

- avoid overwriting existing files without explicit permission
- fail when an initialization destination already exists
- avoid deleting files outside known generated directories
- preserve source files during cleaning
- make destructive behavior visible
- prefer reversible operations where practical

Future commands such as `split`, `flatten`, and `archive` require especially careful file-safety design.

---

## Future Command Design

### `split`

The `split` command uses explicit `% kicho:section NAME` and `% kicho:end`
markers. Explicit markers avoid attempting to parse arbitrary TeX structure.
All markers and output paths are validated before writes begin. The original
`main.tex` is preserved as a backup, and existing section files are never
overwritten.

### `flatten`

The `flatten` command recursively expands full-line `\input` and `\include`
statements. Restricting expansion to complete lines keeps the MVP behavior
explicit and avoids pretending to be a complete TeX parser. Paths are confined
to the project, cycles are rejected, and output is written to `dist/main.tex`
without changing source files.

### `archive`

The `archive` command creates a reproducible, timestamped snapshot without
modifying the project source.

The snapshot contains:

- source files
- bibliography files
- figures
- configuration
- the compiled PDF when available
- JSON metadata containing the Kicho version, creation time, and project name
- read-only Git branch, commit, and dirty-state metadata when available

Generated temporary files other than the compiled PDF are excluded. Git is
queried before archive output is created so the archive itself does not affect
the recorded dirty state. Kicho must not perform Git mutations as part of
archiving.

### `submit`

The `submit` command prepares a new local `submission/` directory containing a
flattened main document, bibliography, figures, build configuration, compiled
PDF when available, and a JSON manifest. It never uploads files and never
overwrites an existing package.

---

## Implementation Strategy

The current implementation uses a shell script.

This is appropriate while Kicho remains small because it provides:

- direct access to system commands
- minimal dependencies
- fast development
- transparent behavior

The implementation should remain in shell while:

- command parsing remains simple
- file transformations remain manageable
- portability requirements remain limited
- maintenance remains understandable

A migration to another language should only occur when shell becomes a genuine limitation.

Possible future reasons for migration include:

- complex configuration parsing
- substantial TeX source transformation
- cross-platform support
- structured error reporting
- extensive automated testing
- package distribution requirements

The language choice should follow project needs rather than fashion.

---

# Design Philosophy

Kicho is a workflow manager for LaTeX research projects.

Its primary purpose is to manage the lifecycle of a research project while coordinating existing tools into a reproducible workflow.

Kicho is intentionally designed as an orchestration layer rather than a replacement for established tools.

The project follows one fundamental principle:

> **Kicho manages research projects, not research itself.**

---

# Scope

Kicho manages the lifecycle of a LaTeX research project.

The intended workflow is:

```text
Project Initialization
        ↓
Writing
        ↓
Building
        ↓
Project Organization
        ↓
Submission Preparation
        ↓
Archive
```

Kicho focuses on managing the project and its workflow, rather than every aspect of the research process.

---

# Responsibilities

Kicho is responsible for:

- initializing research projects
- maintaining a consistent project structure
- coordinating document builds
- organizing project files
- preparing submission packages
- archiving completed projects

These responsibilities define the core scope of Kicho.

---

# Non-Goals

Kicho does **not** attempt to replace existing tools.

Instead, it builds upon them.

Examples include:

- Git
- GitHub
- latexmk
- LuaLaTeX
- Biber
- VS Code
- TeXShop
- Zotero
- arXiv

These tools already solve their respective problems well.

Whenever possible, Kicho delegates specialized tasks to them instead of reimplementing their functionality.

---

# Design Principles

Every new feature should satisfy the following principles.

## Workflow First

A feature should improve the lifecycle of a research project.

Features that are unrelated to project workflow generally do not belong in Kicho.

---

## Orchestration over Reinvention

Kicho should coordinate existing tools rather than replace them.

Whenever an established tool already provides a reliable solution, Kicho should integrate with it instead of introducing a new implementation.

---

## Convention over Configuration

Kicho should prefer widely accepted LaTeX conventions whenever practical.

Projects generated by Kicho should remain understandable and usable without Kicho itself.

---

## Simplicity

The simplest architecture that satisfies the requirements should be preferred.

Avoid unnecessary abstraction or configuration.

Complexity should be introduced only when justified by practical needs.

---

## Compatibility

Kicho should remain compatible with standard LaTeX workflows.

Users should always be free to continue using:

- latexmk
- LuaLaTeX
- editors
- Git
- external build tools

outside of Kicho.

---

# Design Guideline

When evaluating a new feature, ask the following question first:

> **Does this improve the lifecycle of a LaTeX research project?**

If the answer is **no**, the feature probably does not belong in Kicho.

If the answer is **yes**, the next question is:

> **Can an existing tool already do this well?**

If so, Kicho should integrate with that tool rather than replace it.

Only functionality that is unique to Kicho should be implemented within Kicho itself.

---

## Documentation Architecture

Kicho documentation is divided by responsibility.

### `README.md`

For first-time users.

Contains:

- project overview
- installation
- quick start
- implemented features
- project philosophy

### `SPEC.md`

Defines user-visible behavior.

Contains:

- commands
- arguments
- options
- exit behavior
- project detection
- compatibility promises

### `DESIGN.md`

Explains internal architecture and rationale.

### `TODO.md`

Tracks implementation priorities and unfinished work.

### `AI.md`

Defines rules for AI-assisted development.

These roles should remain separate to avoid turning the README into a complete internal manual.

---

## Development Principles

Kicho development should follow these principles:

1. Implement the smallest coherent feature first.
2. Keep the command-line interface stable.
3. Preserve compatibility with standard LaTeX tools.
4. Avoid introducing configuration before it is needed.
5. Prefer explicit behavior over hidden automation.
6. Protect user files.
7. Update the specification when user-visible behavior changes.
8. Update the design document when architecture changes.
9. Distinguish clearly between implemented and planned features.
10. Do not let documentation describe features that do not exist.

---

## Current Design Decisions

The following decisions are currently accepted:

- Kicho is a workflow manager, not only a template generator.
- The CLI is organized around subcommands.
- `latexmk` remains the build engine.
- `.latexmkrc` remains the current build configuration.
- `.latexmkrc` is temporarily used for project detection.
- `main.tex` is the current default main document.
- The main document should become configurable later.
- A dedicated `kicho.toml` file may be introduced in the future.
- New projects should support single-file writing.
- Multi-file organization should remain optional.
- Build artifacts belong in `build/`.
- Cleaning must never remove source files.
