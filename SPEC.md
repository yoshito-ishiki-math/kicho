# newpaper Specification

## Purpose

newpaper is a project generator for TeX documents.

It is intended mainly for mathematical writing.

---

## Basic Behavior

- Generate a new project.
- Never overwrite an existing directory.
- Generate into the current directory unless the user specifies a path.

---

## Project Types

Currently supported:

- English paper
- Japanese paper

Future:

- Blog
- Book

---

## Compilation

Default engine:

- LuaLaTeX
- latexmk

Output directory:

build/

---

## Design Principles

- Keep the generated project simple.
- Use standard LaTeX whenever possible.
- Avoid editor-specific settings unless necessary.

## Command Line Interface

Basic usage:

newpaper <directory>

Examples:

newpaper MyPaper
newpaper MyPaper --english
newpaper MyPaper --japanese

## Safety

The program must:

- Never overwrite an existing directory.
- Fail with a clear error message.
- Create only files inside the target directory.

## Portability

The generated project should work with

- macOS
- Linux

Windows support is desirable but optional.

## Project Layout

The generated project should contain

- main.tex
- preamble/
- sections/
- figures/
- bib/
- build/


## Non-goals

The project is not intended to

- replace full-featured LaTeX IDEs.
- generate publisher-specific templates by default.
- manage bibliography databases.