# Kicho

Kicho is a command-line workflow manager for LaTeX research projects.

It aims to support the entire lifecycle of mathematical writing, from project creation to journal submission, while remaining compatible with standard LaTeX workflows.

The current version provides project initialization, building, cleaning,
environment diagnostics, and project snapshots.

---

## Features

### Current

- Create a new LaTeX research project
- Build the project using `latexmk`
- Clean generated build files
- Check the local environment with `doctor`
- Create source, PDF, and metadata snapshots with `archive`
- Show command-specific help with `help COMMAND`
- Built-in help (`--help`)
- Version information (`--version`)

### Planned

- Split large documents
- Flatten projects for journal submission
- Submission workflow
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

Create a snapshot of the source, compiled PDF, and project metadata.

```bash
../bin/kicho archive
```

Show available commands.

```bash
../bin/kicho --help
```

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

Current releases implement the basic project commands and archive snapshots.
Document transformation and submission functionality remain planned.

---

## Philosophy

Kicho is not simply a LaTeX template.

Its goal is to provide a reproducible and lightweight workflow for mathematical writing while remaining close to standard LaTeX tools such as `latexmk`, LuaLaTeX, and Biber.

Rather than replacing existing tools, Kicho integrates them into a consistent project workflow.

---

## License

MIT License
