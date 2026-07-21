# AI Development Guidelines

This document defines how AI assistants should contribute to the Kicho project.

The goal is not merely to generate code, but to preserve the philosophy, architecture, and long-term consistency of the project.

---

# Purpose

AI should assist the development of Kicho while respecting its design philosophy.

The primary objective is to help build a coherent and maintainable workflow manager for LaTeX research projects.

AI should prioritize architectural consistency over feature quantity.

---

# Project Philosophy

Kicho is a workflow manager for LaTeX research projects.

Its purpose is to manage the lifecycle of a research project by coordinating existing tools into a reproducible workflow.

Kicho manages research projects, not research itself.

AI should always preserve this philosophy.

---

# General Rules

- Prefer simple solutions.
- Prefer explicit behavior over implicit behavior.
- Prefer standard tools over custom implementations.
- Avoid unnecessary abstraction.
- Preserve backward compatibility whenever practical.

When uncertain, choose the simpler design.

---

# Development Workflow

AI should follow the development process below.

```text
Idea
    ↓
Discussion
    ↓
Design (if necessary)
    ↓
Specification
    ↓
Implementation
    ↓
Testing
    ↓
Documentation
```

Implementation should never come before the specification.

---

# Design Rules

Before proposing a new feature, ask the following questions.

## 1. Does this improve the lifecycle of a LaTeX research project?

If the answer is no, the feature probably does not belong in Kicho.

## 2. Can an existing tool already solve this problem?

If yes, Kicho should integrate with that tool rather than replace it.

## 3. Is this functionality unique to Kicho?

Only functionality that is unique to Kicho should be implemented within Kicho itself.

---

# Orchestration over Reinvention

Kicho coordinates existing tools.

It should not replace them.

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

AI should avoid proposing replacements for these tools.

Instead, AI should improve how Kicho works together with them.

---

# Documentation Rules

Documentation should remain consistent.

Each document has a single responsibility.

| Document | Purpose |
|----------|---------|
| README.md | Project introduction |
| SPEC.md | User-visible command specification |
| DESIGN.md | Internal architecture |
| ROADMAP.md | Long-term development plan |
| CHANGELOG.md | Release history |
| CONTRIBUTING.md | Contribution guidelines |
| CONTEXT.md | Historical background |
| REVIEW.md | Future architectural discussions |
| AI.md | AI development guidelines |

Avoid duplicating information across multiple documents.

---

# Coding Rules

Prefer small and readable implementations.

Avoid introducing complexity before it is necessary.

Refactor only when complexity justifies it.

Keep dependencies minimal whenever possible.

Maintain compatibility with standard LaTeX workflows.

---

# Communication Rules

When discussing new ideas:

- explain the motivation
- discuss trade-offs
- separate facts from opinions
- distinguish implemented features from future ideas

Do not present speculative ideas as completed functionality.

---

# Things to Avoid

Avoid proposing features that:

- replace existing tools
- significantly expand the project scope
- introduce unnecessary configuration
- duplicate functionality already provided elsewhere

Kicho should remain focused.

---

# Decision Rule

When evaluating any proposal, ask:

> Does this improve the lifecycle of a LaTeX research project?

Then ask:

> Can an existing tool already do this well?

If the answer to the second question is yes, Kicho should integrate with that tool rather than replace it.

---

# Core Principle

When uncertain, preserve the project's philosophy instead of maximizing the number of features.

A smaller, simpler, and more coherent design is always preferred over a larger but less focused one.
