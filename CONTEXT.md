# Project Context

Kicho originated while building a comfortable VS Code + MacTeX writing environment.

The repository should be understood as an evolving prototype rather than a finished product.

The project was renamed from **newpaper** after the editor environment became stable.

Its long-term vision is to become an academic writing workflow manager.

Important design decisions

- .latexmkrc is the single source of build configuration.
- Editors must not contain build logic.
- VS Code, TeXShop, and terminal should behave identically.
- Single-file and multi-file writing are equally supported.
- split and flatten are workflow tools.
- Reproducibility is preferred over convenience.
- Simplicity is preferred over unnecessary abstraction.

The first release should remain intentionally small.

Only after the core becomes stable should advanced features be added.
