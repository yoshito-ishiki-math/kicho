# AI.md

# AI Development Guide for newpaper

This document describes the development philosophy of this project.
Any AI assistant (Codex, ChatGPT, Claude, Gemini, etc.) should read this file before modifying the project.

---

# Project

newpaper is a lightweight project generator for mathematical TeX documents.

The goal is to provide a clean starting point rather than a complete writing environment.

The generated project should remain understandable by ordinary LaTeX users.

---

# Long-term vision

The project aims to become a reliable project generator for mathematical writing.

Possible targets include

- English research papers
- Japanese papers
- Lecture notes
- Blog articles
- Books

Publisher-specific templates may be added later.

---

# Design Principles

## Simplicity

Prefer simple code over clever code.

Avoid unnecessary dependencies.

Prefer POSIX shell/Bash unless there is a compelling reason to migrate.

---

## Predictability

The tool should behave like a normal UNIX command.

Examples:

- generate into the current directory
- never overwrite existing directories
- fail loudly instead of silently changing behavior

---

## Maintainability

Keep templates separated from the generator.

The generator should contain logic only.

Template contents should live inside

templates/

rather than being embedded in the shell script.

---

## Backward compatibility

Avoid breaking existing commands.

Changing the command-line interface requires updating

- README.md
- SPEC.md
- CHANGELOG.md

---

# Documentation

Whenever behavior changes:

- update SPEC.md
- update README.md if users are affected
- update CHANGELOG.md
- update TODO.md when appropriate

Do not allow the documentation to become inconsistent with the implementation.

---

# Coding Style

Prefer

- small functions
- descriptive variable names
- readable shell code

Avoid

- duplicated template code
- deeply nested conditionals

---

# Repository Structure

The intended structure is

newpaper/
    newpaper
    templates/
    docs/
    README.md
    SPEC.md
    AI.md
    CHANGELOG.md
    TODO.md

---

# Future Ideas

Possible future features

- --english
- --japanese
- --blog
- --book
- --help
- --version
- interactive mode
- Git initialization
- VS Code integration
- arXiv template
- publisher templates

These are ideas, not requirements.

---

# Non-goals

The project is NOT intended to become

- a LaTeX IDE
- a bibliography manager
- a package manager

Keep the scope focused.

---

# Before Making Changes

Before implementing a new feature, ask:

1. Does this simplify the user's workflow?
2. Does this keep the generated project clean?
3. Is this feature general enough?
4. Can this be implemented without breaking existing users?

If the answer to any question is "no", reconsider the design.

---

# Final Rule

Prefer a small, stable, and understandable tool over a feature-rich but complicated one.

# Notes for Future AI Assistants

The primary user of this project is a mathematician.

When proposing new features,

prioritize

- mathematical writing
- reproducibility
- portability
- long-term maintainability

over adding many options.

The project should remain useful even after several years.

I added the following information.

# AI Guidelines

This document explains the long-term philosophy of Kicho.

## Project

Kicho is **not** merely a LaTeX template generator.

Its goal is to become a workflow manager for academic writing.

The target users are researchers writing mathematical papers over many years.

The project values

- reproducibility
- portability
- editor independence
- minimal configuration
- maintainability

rather than feature richness.

---

## Repository history

This repository originated while building a VS Code + MacTeX writing environment.

Originally the project was called **newpaper**.

After the editor environment became stable, the project was separated and renamed **Kicho**.

Therefore the repository currently contains

- experimental code
- temporary specifications
- remnants of the old name
- unfinished documentation

This is expected.

Do not assume inconsistencies are design mistakes.

---

## Build philosophy

Build configuration must be centralized in

    .latexmkrc

Editors never define build logic.

The intended workflow is

VS Code
    ↓
LaTeX Workshop
    ↓
latexmk
    ↓
.latexmkrc
    ↓
LuaLaTeX + biber

TeXShop
    ↓
latexmk
    ↓
.latexmkrc

Terminal
    ↓
latexmk
    ↓
.latexmkrc

Every editor should produce identical output.

---

## Development philosophy

Implement the smallest useful feature first.

The first milestone is

    kicho init

Later features include

- build
- clean
- archive
- split
- flatten

split and flatten are expected to become the distinguishing features of Kicho.

---

## Coding philosophy

Prefer

- simple code
- explicit behavior
- minimal dependencies

Avoid unnecessary abstraction.

Do not over-engineer early versions.

Grow the project incrementally.
