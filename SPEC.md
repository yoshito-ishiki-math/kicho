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
```

Future functionality should normally be introduced as additional subcommands.

---

## Commands

### `init`

Create a new LaTeX research project.

#### Usage

```bash
kicho init PROJECT
```

#### Arguments

| Name | Description |
|---|---|
| `PROJECT` | Name or path of the project directory to create |

#### Behavior

The command creates a new directory from Kicho's built-in project template.

The command fails if:

- the project name is omitted
- a file or directory already exists at the destination
- the project template cannot be copied

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

Build behavior is delegated to the project's `.latexmkrc`.

The current project template uses:

- LuaLaTeX
- Biber
- the `build/` output directory
- `main.tex` as the main document

Kicho does not directly duplicate the compilation settings stored in `.latexmkrc`.

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

## Global Options

### Help

Display command-line help.

```bash
kicho --help
kicho -h
```

Calling `kicho` without a command also displays the help message.

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
kicho 0.1.0
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

User-facing errors should:

- state what failed
- avoid unnecessary implementation details
- suggest the relevant help command when appropriate

Example:

```text
Error: unknown command 'example'.
Run 'kicho --help' for usage.
```

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

## Planned Commands

The following commands are planned but are not currently implemented:

```bash
kicho split
kicho flatten
kicho archive
kicho submit
```

Their detailed behavior is intentionally left unspecified until their design is finalized.

Documentation must clearly distinguish implemented commands from planned commands.

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
