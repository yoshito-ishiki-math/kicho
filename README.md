# Kicho

Kicho is a command-line tool for managing LaTeX research projects.

Current version focuses on creating a clean project template.

Future versions will support project management tasks such as building, splitting, flattening, archiving, and submission preparation.

---

## Features

Current

- Create a new paper project

Planned

- Build project
- Split large documents
- Flatten for journal submission
- Archive projects
- Submission workflow

---

## Installation

```bash
git clone https://github.com/yoshito-ishiki-math/kicho.git
cd kicho

chmod +x bin/kicho
```

---

## Quick Start

Create a paper.

```bash
./bin/kicho init MyPaper
```

Move into the directory.

```bash
cd MyPaper
```

Compile.

```bash
latexmk main.tex
```

---

## Generated project

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

## Philosophy

Kicho aims to provide a complete workflow for mathematical writing.

Instead of being only a LaTeX template, Kicho intends to manage the entire lifecycle of a paper:

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

The project emphasizes simplicity, reproducibility, and compatibility with standard LaTeX workflows.

---

## License

MIT License
