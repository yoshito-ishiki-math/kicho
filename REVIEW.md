# Kicho Design Review

This document records architectural concerns that may deserve future design
work. These are review topics, not committed roadmap items. Concrete work lives
in `TODO.md` or GitHub Issues once approved.

## Documentation

The root documents have distinct responsibilities:

| Document | Purpose |
|----------|---------|
| `README.md` | User introduction |
| `SPEC.md` | User-visible command behavior |
| `DESIGN.md` | Internal architecture and invariants |
| `TODO.md` | Implemented work and remaining priorities |
| `CHANGELOG.md` | Release history |
| `CONTRIBUTING.md` | Contribution process |
| `AI.md` | Rules for AI-assisted development |
| `CONTEXT.md` | Historical background |
| `REVIEW.md` | Architectural topics not yet accepted |

Do not duplicate short-term tasks across `TODO.md`, this file, and GitHub
Issues. Moving documents under `docs/` is not justified while the root remains
small and direct links are stable.

## Command Architecture

Commands are discovered from `lib/kicho/commands/*.sh`. Shared infrastructure
belongs in narrowly scoped modules under `lib/kicho/`; command files should
contain command-specific parsing and behavior. Preserve the optional metadata
function protocol used for help, aliases, and requirements.

Reconsider further extraction only when a command has multiple independently
testable responsibilities. Avoid a framework or object system for this small
Bash CLI.

## File Transformations

`split`, `flatten`, `archive`, and `submit` must continue to validate all known
paths before publication. Multi-file writes should stage output first and roll
back only files created by the current invocation when a later write fails.

Potential future work:

- dry-run output for file-transforming commands;
- failure-injection coverage for archive creation;
- a safe command for combining selected sections in an explicit order.

## Templates

English `amsart` and Japanese `jlreq` templates are the current supported
interface. Before adding article, book, or Beamer variants, define required
files, compatibility expectations, and an upgrade policy for existing projects.

CI should keep real LuaLaTeX smoke builds separate from the fast Bash test
suite. Local command tests should remain deterministic and use fake external
tools where the external tool's behavior is not under test.

## Scope

Kicho coordinates established tools such as Git, latexmk, LuaLaTeX, Biber,
editors, and submission services. It should not become a general research
manager or reimplement TeX parsing, version control, or publication services.
