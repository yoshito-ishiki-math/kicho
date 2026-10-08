# Kicho

English | [日本語](README.ja.md)

Kicho is a command-line workflow manager for LaTeX research projects.

It aims to support the entire lifecycle of mathematical writing, from project creation to journal submission, while remaining compatible with standard LaTeX workflows.

The current version provides project initialization, building, cleaning,
environment diagnostics, project validation, source transformations, snapshots,
and local submission packages.

---

## Features

### Current

- Create a new LaTeX research project
- Choose an English or Japanese built-in paper template
- Build the project using `latexmk`
- Clean generated build files
- Check the local environment with `doctor`
- Validate project files and references with `check`
- Create source, PDF, and metadata snapshots with `archive`
- Split explicitly marked source blocks with `split`
- Flatten full-line `\input` and `\include` commands with `flatten`
- Create a local submission package with `submit`
- Create an arXiv source ZIP and metadata worksheet with `submit --arxiv`
- Show command-specific help with `help COMMAND`
- Show command-specific help with `COMMAND --help`
- Built-in help (`--help`)
- Version information (`--version`)

### Planned

- More complete TeX-aware transformations
- Submission profiles
- Project management utilities

---

## Installation

```bash
git clone https://github.com/yoshito-ishiki-math/kicho.git
cd kicho

chmod +x bin/kicho
```

---

## Quick Start

Create a new project.

```bash
./bin/kicho init MyPaper
```

Create a Japanese LuaLaTeX project using `jlreq`, LuaLaTeX-ja, and the
Harano Aji fonts included with TeX Live.

```bash
./bin/kicho init --template japanese MyJapanesePaper
```

Move into the project directory.

```bash
cd MyPaper
```

Build the project.

```bash
../bin/kicho build
```

Clean generated files.

```bash
../bin/kicho clean
```

Diagnose the installed toolchain, then validate the project without building.

```bash
../bin/kicho doctor
../bin/kicho check
```

Diagnostics include source filenames and line numbers. Use `../bin/kicho check --json` for structured output. Literal graphic paths and input cycles are checked.

Create a snapshot of the source, compiled PDF, and project metadata.

```bash
../bin/kicho archive
```

Prepare an arXiv upload ZIP. `--build` refreshes the PDF, bibliography, and dependency record before packaging.

```bash
../bin/kicho submit --arxiv --build
```

The command keeps `.bib` files out of the upload ZIP and includes `main.bbl`.
It also creates a project-root `arxiv-metadata.txt` draft for review and reuse.
Kicho does not upload the package.

Choose a different project-local output directory when keeping an earlier
package or preparing a revision:

```bash
../bin/kicho submit --arxiv --build --output submissions/revision-2
```

Kicho refuses existing output directories and does not provide a destructive
force-overwrite option.

Show available commands.

```bash
../bin/kicho --help
```

---

## Testing

Install the development-time shell linter on macOS.

```bash
brew install shellcheck
```

Then run the complete lint, syntax, and integration test suite from the
repository root.

```bash
bash tests/run.sh
```

Pushes and pull requests run the same suite on macOS 14 with the system
`/bin/bash` to preserve Bash 3.2 compatibility.

---

## VS Code and iCloud Drive

The generated workspace settings make LaTeX Workshop use `latexmk` for both
manual and save-triggered builds. They disable TeX-program magic comments and
pass the relative filename `%DOCFILE_EXT%`, which avoids sending an absolute
iCloud Drive path containing spaces or `~` directly to LuaLaTeX.

The PDF viewer is configured to open `build/main.pdf`. Kicho intentionally does
not generate `main.pdf` in the project root.

Kicho also keeps LuaTeX's font cache under `build/texmf-var/` when `TEXMFVAR`
has not been set explicitly. This avoids font-cache permission failures in
restricted shells and agent environments. The setting is shared by `kicho
build`, direct `latexmk` runs, and the generated LaTeX Workshop configuration.
Run `kicho doctor` to inspect cache writability. Existing explicit `TEXMFVAR`
settings are preserved.

Keep engine selection in `.latexmkrc`. Do not add a line such as this to
`main.tex`:

```tex
% !TEX program = lualatex
```

If an older project exhibits this problem, remove the magic comment and use the
workspace settings from a newly generated Kicho project.

---

## Generated Project Structure

```
MyPaper/
├── main.tex
├── preamble/
├── sections/
├── bib/
├── figures/
├── build/
└── .latexmkrc
```

---

## Workflow

Kicho is designed around the following workflow.

```
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

Current releases implement the basic project commands, archive snapshots,
marker-based splitting, safe flattening, and local submission packages.

---

## Philosophy

Kicho is not simply a LaTeX template.

Its goal is to provide a reproducible and lightweight workflow for mathematical writing while remaining close to standard LaTeX tools such as `latexmk`, LuaLaTeX, and Biber.

Rather than replacing existing tools, Kicho integrates them into a consistent project workflow.

---

## Project paths

Project paths can be configured in a literal `kicho.conf`:

```text
main = paper.tex
build_dir = output
```

Global `--main` / `--build-dir` options override environment settings and the
project file. `kicho check --log --json` includes TeX-log diagnostics, and
`kicho build --strict` fails on unresolved citations/references. Export
manifests include file hashes and TeX tool versions. See [SPEC.md](SPEC.md) for
precedence, safety rules, and the provenance schema.

## License

MIT License

## Paragraph IDs and editorial notes

Kicho distributes the paragraph-ID package and helper. Existing manuscripts retain their IDs and local package versions.

```bash
kicho paraids install --root MyPaper
kicho paraids new --root MyPaper --count 3
kicho paraids check --root MyPaper
```

`submit` and `submit --arxiv` disable IDs and red notes in their release copy; standard submission with review marks rebuilds the clean PDF. `submit --build` refreshes working outputs for either submission mode. These operations require Python 3.9 or later. See [usage](docs/paragraphids.md) and [the command specification](SPEC.md#paraids).
