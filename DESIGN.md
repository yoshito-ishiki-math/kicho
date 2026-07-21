# DESIGN.md

# Kicho Design Philosophy

## Purpose

Kicho is not merely a LaTeX template generator.

Its long-term goal is to become a workflow manager for academic writing.

The primary target users are researchers, especially those writing mathematical papers over many years.

The project emphasizes reproducibility, maintainability, portability, and simplicity rather than providing a large number of features.

---

# Project History

Kicho originated while building a comfortable LaTeX writing environment based on VS Code and MacTeX.

The project was initially developed under the name **newpaper**.

After the editor environment became sufficiently stable, the project was separated into an independent repository and renamed **Kicho**.

As a result, the repository currently contains remnants of the old implementation, temporary specifications, and experimental code.

These inconsistencies should be understood as artifacts of an ongoing transition rather than design mistakes.

---

# Design Principles

## Editor Independence

Kicho must not depend on a particular editor.

The supported editors include

* VS Code
* TeXShop
* Terminal
* Future editors

All editors should behave identically.

Editors are responsible only for editing, previewing PDFs, SyncTeX, and optional automatic compilation.

The build system itself must remain independent of the editor.

---

## Single Source of Build Configuration

The build configuration is centralized in

```
.latexmkrc
```

No editor should define its own build logic.

The intended build flow is

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

Every supported environment should produce identical output.

---

## Workflow Before Features

Kicho is designed around the research workflow rather than around LaTeX itself.

The intended workflow is

kicho init

↓

Write the paper

↓

Optionally split the source

↓

Flatten before submission

↓

Archive the project

The workflow should remain simple and reproducible.

---

## Single-file and Multi-file Projects

Kicho does not force users to choose between single-file and multi-file projects.

Both are first-class workflows.

The user should be free to switch between them whenever appropriate.

The commands

* split
* flatten

exist to support workflow transitions rather than to enforce one project structure.

They should be designed as practical tools instead of mathematically exact inverse operations.

---

## Incremental Development

Kicho should grow gradually.

The first release should implement only the smallest useful feature.

Current priority:

1. kicho init

Later additions:

* build
* clean
* archive
* split
* flatten

Advanced functionality should be implemented only after the core workflow becomes stable.

---

## Simplicity

Prefer

* simple implementations
* explicit behavior
* readable code
* minimal dependencies

Avoid unnecessary abstraction.

Avoid implementing future ideas before they become necessary.

---

## Reproducibility

A generated project should remain usable for many years.

Users should be able to clone a repository and obtain identical build results regardless of editor.

Project structure should be predictable and easy to understand.

---

## Scope

Kicho focuses on managing the writing workflow.

It is not intended to become a general-purpose IDE, package manager, or bibliography manager.

External tools such as Git, latexmk, biber, and editors should be integrated rather than replaced.

---

## Long-Term Vision

The long-term vision is to provide a lightweight but reliable environment for academic writing.

The project should help researchers spend less time configuring tools and more time doing research.

Every new feature should be evaluated according to one question:

> Does this improve the workflow of writing and maintaining research papers?

If the answer is no, the feature probably does not belong in Kicho.
