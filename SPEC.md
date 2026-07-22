# Kicho Specification

This document defines the command-line interface and user-visible behavior of Kicho.

The README explains what Kicho is and provides a quick introduction.

This specification defines how Kicho commands behave.

---

## Command-Line Interface

Kicho uses a subcommand-oriented command-line interface.

```text
kicho <command> [arguments] [options]
```

Examples:

```bash
kicho init MyPaper
kicho build
kicho clean
kicho doctor
kicho check
```

Future functionality should normally be introduced as additional subcommands.

---

## Commands

### `init`

Create a new LaTeX research project.

#### Usage

```bash
kicho init PROJECT
kicho init --template TEMPLATE PROJECT
```

#### Arguments

| Name | Description |
|---|---|
| `PROJECT` | Name or path of the project directory to create |

#### Options

| Name | Description |
|---|---|
| `-t, --template TEMPLATE` | Select a built-in project template |

Available template names are:

| Name | Description |
|---|---|
| `english` | English mathematical paper using `amsart` (default) |
| `japanese` | Japanese mathematical paper using `jlreq` and LuaLaTeX-ja |

#### Behavior

The command creates a new directory from Kicho's built-in project template.

The command fails if:

- the project name is omitted
- more than one project name is supplied
- an option is missing its value
- an unknown template is requested
- a file or directory already exists at the destination
- the project template cannot be copied

The generated `build/` directory starts empty except for its tracked placeholder,
even if the local template directory contains ignored build artifacts.

Generated root documents do not contain a `% !TEX program` magic comment.
Compilation mode is owned by `.latexmkrc`; editor integrations must invoke
`latexmk` rather than selecting a TeX engine independently.

The built-in templates include a LaTeX Workshop workspace configuration that:

- uses the `latexmk` recipe for manual and automatic builds
- disables TeX-program magic comments
- passes the relative root filename through `%DOCFILE_EXT%`
- points the integrated PDF viewer at `%DIR%/build`

Using a relative filename avoids passing iCloud Drive paths containing spaces
or literal `~` characters directly to LuaLaTeX.

#### Exit Status

| Code | Meaning |
|---|---|
| `0` | Project created successfully |
| `1` | An error occurred |

---

### `build`

Build the current LaTeX project.

#### Usage

```bash
kicho build
```

#### Current Requirements

- the command is run from the root of a Kicho project
- `.latexmkrc` exists in the current directory
- `latexmk` is installed and available through `PATH`

#### Behavior

The command runs:

```bash
latexmk
```

The command does not accept arguments.

Build behavior is delegated to the project's `.latexmkrc`.

The current project template uses:

- LuaLaTeX
- Biber
- the `build/` output directory
- `main.tex` as the main document

Kicho does not directly duplicate the compilation settings stored in `.latexmkrc`.

Editor recipes should likewise call `latexmk` and leave engine selection and
flags to `.latexmkrc`.

#### Future Configuration

The main document may become configurable in a future release.

For example, a project may eventually specify:

```text
main.tex
paper.tex
book.tex
```

The configuration format has not yet been finalized.

A future version may introduce a Kicho-specific configuration file such as:

```text
kicho.toml
```

#### Exit Status

Kicho preserves the success or failure of the underlying build process.

| Code | Meaning |
|---|---|
| `0` | Build completed successfully |
| nonzero | The build failed |

---

### `clean`

Remove generated LaTeX build files.

#### Usage

```bash
kicho clean
```

#### Current Requirements

- the command is run from the root of a Kicho project
- `.latexmkrc` exists in the current directory
- `latexmk` is installed and available through `PATH`

#### Behavior

The command first runs:

```bash
latexmk -C
```

The command does not accept arguments.

It then removes the generated `build/` directory.

Source files such as the following must not be removed:

```text
main.tex
preamble/
sections/
bib/
figures/
.latexmkrc
```

#### Exit Status

| Code | Meaning |
|---|---|
| `0` | Generated files were removed successfully |
| nonzero | Cleaning failed |

---

### `doctor`

Diagnose the Kicho installation and the external LaTeX environment.

#### Usage

```bash
kicho doctor
```

The command can run inside or outside a Kicho project. It checks the Kicho
installation, required commands (`bash`, `latexmk`, `lualatex`, and `biber`),
and optional Git availability. Project files are intentionally handled by
`kicho check`.

Warnings do not make the command fail. A missing required command or a broken
Kicho installation is a failure.

#### Exit Status

| Code | Meaning |
|---|---|
| `0` | Required checks passed, with or without warnings |
| `1` | One or more required checks failed |

---

### `check`

Validate the structure and statically discoverable file references of the
current project.

#### Usage

```bash
kicho check
```

The MVP checks:

- `main.tex`
- `.latexmkrc`
- literal `\input{...}` and `\include{...}` references, recursively
- literal `\addbibresource{...}` and `\bibliography{...}` references
- literal `\includegraphics{...}` references
- the conventional `bib/` and `figures/` directories

Paths generated through TeX macros cannot be resolved safely by the MVP and
produce warnings. References that resolve outside the project, reference a
symbolic link, or name a missing file are errors. The check is static and does
not replace a real LaTeX build.

Missing optional conventional directories produce warnings. Missing required
project files or referenced files produce errors.

#### Exit Status

| Code | Meaning |
|---|---|
| `0` | No errors were found, with or without warnings |
| `1` | One or more errors were found |

---

## Global Options

### Help

Display command-line help.

```bash
kicho --help
kicho -h
kicho help
kicho help COMMAND
kicho COMMAND --help
kicho COMMAND -h
```

Calling `kicho` without a command also displays the help message.

`kicho help COMMAND` displays the command's summary, usage, examples, and
aliases when those fields are available. If a command does not define its own
usage text, Kicho displays a minimal default usage line.

The help command does not run the target command or check its runtime
requirements.

The command-specific `--help` and `-h` forms are equivalent to
`kicho help COMMAND`. They must also work when the current directory or external
tools do not satisfy the command's runtime requirements.

### Version

Display Kicho's version.

```bash
kicho --version
kicho -v
```

The current output format is:

```text
kicho VERSION
```

Example:

```text
kicho 0.2.0-alpha.1
```

---

## Error Handling

Kicho reports an error when:

- an unknown command is supplied
- a required argument is missing
- the destination for `init` already exists
- `.latexmkrc` cannot be found
- `latexmk` is not installed or is unavailable through `PATH`
- an underlying command such as `latexmk` fails

Diagnostic messages are written to standard error.

Normal command results and diagnostic reports from `doctor` and `check` are
written to standard output. Operational warnings from commands that create or
copy files are written to standard error.

User-facing errors should:

- state what failed
- avoid unnecessary implementation details
- suggest the relevant help command when appropriate

Example:

```text
Error: unknown command 'example'.
Run 'kicho --help' for usage.
```

Invalid arguments return status `1`. Commands that delegate to an external
program preserve that program's nonzero status where practical.

---

## Project Detection

In the current implementation, a directory is considered a Kicho project when it contains:

```text
.latexmkrc
```

This is intentionally a minimal rule.

A future release may introduce a dedicated Kicho configuration file, potentially named:

```text
kicho.toml
```

Such a file could identify the project explicitly and store settings such as:

- the main TeX document
- the build directory
- project metadata
- archive behavior
- submission settings

The dedicated configuration format is not part of the current specification.

---

## Generated Project Structure

A newly initialized project currently has a structure similar to:

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

The exact contents of template directories may evolve while preserving the general workflow.

Generated build artifacts should be placed in:

```text
build/
```

For the default main document, the compiled PDF is therefore:

```text
build/main.pdf
```

The absence of `main.pdf` in the project root is expected. Editor integrations
should view `build/main.pdf` without changing the build destination.

---

## Build Architecture

Kicho delegates compilation to the existing LaTeX toolchain.

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

Kicho should coordinate standard tools rather than replace their configuration systems unnecessarily.

The same `.latexmkrc` should be usable from:

- Kicho
- the terminal
- Visual Studio Code
- TeXShop
- other editors that support `latexmk`

---

## CLI Design Principles

Kicho uses subcommands as its primary interface.

Preferred form:

```bash
kicho build
kicho clean
kicho split
kicho flatten
```

New major operations should generally be added as subcommands rather than unrelated global options.

Global options should be reserved for behavior applying to Kicho itself, such as:

```bash
kicho --help
kicho --version
```

---

## `archive` Command

Create a read-only snapshot of the current project.

```bash
kicho archive
```

The command requires a Kicho project and does not accept arguments. It creates:

```text
archives/YYYY-MM-DD_HH-MM-SS/
├── source/
├── pdf/
│   └── main.pdf
└── metadata/
    └── archive.json
```

The source snapshot copies `main.tex`, `sections/`, `preamble/`, `figures/`,
`bib/`, and `.latexmkrc` when present. Missing source entries produce warnings
without failing the archive.

If `build/main.pdf` exists, it is copied to `pdf/main.pdf`. A missing PDF
produces a warning and leaves the `pdf/` directory empty.

`archive.json` records the Kicho version, creation time, and project directory
name. When the project is inside a Git work tree with a valid `HEAD`, it also
records the branch (or `HEAD` when detached), commit, and dirty state. Kicho
only reads Git information and does not modify the repository.

Archive paths are never reused. The command fails if the timestamped destination
already exists.

---

## `split` Command

Split explicitly marked blocks from `main.tex` into `sections/*.tex`.

```text
% kicho:section introduction
Section contents.
% kicho:end
```

The marker name must match `[a-z0-9][a-z0-9-]*`. Each opening marker must have
one closing marker, blocks cannot be nested, and names cannot be repeated.

After a successful split, the marked block is replaced with:

```tex
\input{sections/introduction}
```

and its contents are written to `sections/introduction.tex`. Kicho validates all
markers and destinations before changing the project, refuses to overwrite an
existing section file, and saves the original as `main.tex.kicho-backup`.

---

## `flatten` Command

Create `dist/main.tex` without modifying the project source.

The command recursively expands `\input{...}` and `\include{...}` statements
that occupy a complete source line. A missing file, an include cycle, an
absolute path, or a path containing a `..` component is an error. `.tex` is
appended when the referenced path has no extension.

Kicho refuses to overwrite an existing `dist/main.tex`.

---

## `submit` Command

Create a local submission package without uploading it anywhere.

```text
submission/
├── main.tex
├── bib/
├── figures/
├── main.pdf          when build/main.pdf exists
├── .latexmkrc
└── manifest.json
```

`main.tex` is generated using the same expansion rules as `flatten`. Missing
optional files produce warnings. Kicho refuses to overwrite an existing
`submission/` directory and does not modify source files or Git state.

---

## Compatibility Policy

Kicho should remain compatible with standard LaTeX projects and tools.

It should not require users to abandon:

- `latexmk`
- `.latexmkrc`
- LuaLaTeX
- Biber
- standard TeX directory structures

Kicho-specific configuration should be introduced only when it provides functionality that cannot be represented cleanly through existing LaTeX tools.
