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
kicho doctor
kicho check
```

Future functionality should normally be introduced as additional subcommands.

---

## Commands

### `paraids`

Manage stable paragraph identifiers through Kicho. Kicho distributes
`paragraphids.sty`; writing skills only describe its use.

```bash
kicho paraids install --root PATH
kicho paraids new --root PATH --count 3
kicho paraids find p-a7f3c921e40b --root PATH
kicho paraids check --root PATH
```

The root defaults to the current directory. `install` copies the bundled
package to an existing manuscript directory without editing any TeX source.
It succeeds without changes for an identical copy and refuses a different
existing copy or a symbolic-link destination. Review customizations before
deliberately replacing an older copy. Existing projects are never upgraded
automatically, and `init` does not insert paragraph tags.

`new`, `find`, and `check` retain the existing helper's literal UTF-8 scanning
and do not edit sources. `new` reserves commented IDs. `find` and `check` accept
`--include-comments`. Directory scans exclude archives, submission/submissions,
build outputs, and Kicho export directories identified by their manifest. An
explicit file or export root can still be searched. Scope other historical
versions explicitly. IDs use `p-` followed by twelve random lowercase
hexadecimal digits.
The package retains the independent show/hide switch, physical-left placement,
and red `\paranote` annotations. See [paragraph-ID usage](docs/paragraphids.md).

The command requires Python 3.9 or later with only its standard library.
Invalid arguments and operational failures are nonzero; `find` also returns
nonzero when the ID is absent, and `check` when IDs are invalid or duplicated.

Both submission modes use the same Python helper on the temporary submission
copy. They comment out literal paragraph-ID and note commands, their package
settings, and paragraphids/showkeys loading. Mixed package lists retain other
packages, multiline notes are fully commented, and already-commented material
is unchanged. The package is omitted. Unsupported or malformed editorial
syntax fails before the destination is created. The helper does not expand TeX
macros; inspect the compiled release when a project uses custom wrappers.

Standard submission rebuilds its PDF from the cleaned copy when editorial
material is present, including commented markers, instead of copying a possibly
annotated working PDF. It requires a successful `latexmk` build and a fresh
`build/main.pdf`. Build intermediates are removed from the package. Untagged
standard submissions retain their existing PDF-copy behavior, with a warning
when known source dependencies are newer than the copied output. `submit --build`
first runs the project build for a current PDF, bibliography, and dependency
record. arXiv submission remains a source-only export. Neither mode edits the working manuscript or
uploads anything. `archive` retains the local package and active review marks.

---

### `init`

Create a new LaTeX research project.

#### Usage

```bash
kicho init PROJECT
kicho init --template TEMPLATE PROJECT
```

#### Arguments

| Name | Description |
|---|---|
| `PROJECT` | Name or path of the project directory to create |

#### Options

| Name | Description |
|---|---|
| `-t, --template TEMPLATE` | Select a built-in project template |

Available template names are:

| Name | Description |
|---|---|
| `english` | English mathematical paper using `amsart` (default) |
| `japanese` | Japanese mathematical paper using `jlreq` and LuaLaTeX-ja |

#### Behavior

The command creates a new directory from Kicho's built-in project template.

The command fails if:

- the project name is omitted
- more than one project name is supplied
- an option is missing its value
- an unknown template is requested
- a file or directory already exists at the destination
- the project template cannot be copied

Option values are validated before required positional arguments. For example,
`kicho init --template unknown` reports the unknown template rather than only
reporting that `PROJECT` is missing.

The generated `build/` directory starts empty except for its tracked placeholder,
even if the local template directory contains ignored build artifacts.

Generated root documents do not contain a `% !TEX program` magic comment.
Compilation mode is owned by `.latexmkrc`; editor integrations must invoke
`latexmk` rather than selecting a TeX engine independently.

The built-in templates include a LaTeX Workshop workspace configuration that:

- uses the `latexmk` recipe for manual and automatic builds
- disables TeX-program magic comments
- passes the relative root filename through `%DOCFILE_EXT%`
- points the integrated PDF viewer at `%DIR%/build`

Using a relative filename avoids passing iCloud Drive paths containing spaces
or literal `~` characters directly to LuaLaTeX.

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
kicho build --strict
```

#### Current Requirements

- the command is run from the root of a Kicho project
- `.latexmkrc` exists in the current directory
- `latexmk` is installed and available through `PATH`

#### Behavior

The command runs:

```bash
latexmk -recorder -outdir=build -auxdir=build main.tex
```

The example uses default paths. `--strict` requires a fresh TeX log without
unresolved citation/reference warnings.

When `TEXMFVAR` is unset, Kicho creates `texmf-var/` under the selected build
directory and exports it to
`latexmk` as a writable project-local LuaTeX font-cache directory. An explicit
non-empty `TEXMFVAR` is preserved. The built-in `.latexmkrc` templates apply
the same unset-only fallback, so direct `latexmk` and LaTeX Workshop builds use
the project-local cache as well.

Build behavior is delegated to the project's `.latexmkrc`.

The current project template uses:

- LuaLaTeX
- Biber
- the `build/` output directory
- `main.tex` as the main document

Kicho does not directly duplicate the compilation settings stored in `.latexmkrc`.

Editor recipes should likewise call `latexmk` and leave engine selection and
flags to `.latexmkrc`.

`kicho doctor` reports whether an explicit `TEXMFVAR`, or the project-local
fallback when no value is set, has a writable directory. An unwritable explicit
setting produces a warning but is not replaced.

#### Project Paths

The main document and generated output directory can be selected in
`kicho.conf`, by environment variables, or by global command options. Engine
settings remain in `.latexmkrc`. See the project-path specification below.

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

After validating the generated directory, the command runs (for default paths):

```bash
latexmk -C -outdir=build -auxdir=build main.tex
```

The command does not accept arguments.

Before invoking latexmk, cleaning refuses a directory containing authored TeX,
bibliography, or style files, or any known source dependency (including figures
and recorder-only data). After latexmk succeeds, Kicho removes only empty build
directories. It never recursively deletes the selected directory: other files
and populated LuaTeX caches are retained. A retained directory is reported.

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

### `doctor`

Diagnose the Kicho installation and the external LaTeX environment.

#### Usage

```bash
kicho doctor
```

The command can run inside or outside a Kicho project. It checks the Kicho
installation, required commands (`bash`, `latexmk`, `lualatex`, and `biber`),
and optional Git, Python 3.9+, and ZIP capabilities. Project files are
intentionally handled by
`kicho check`.

Warnings do not make the command fail. A missing required command or a broken
Kicho installation is a failure.

#### Exit Status

| Code | Meaning |
|---|---|
| `0` | Required checks passed, with or without warnings |
| `1` | One or more required checks failed |

---

### `check`

Validate the structure and statically discoverable file references of the
current project.

#### Usage

```bash
kicho check
kicho check --json
```

The static checker validates:

- `main.tex`
- `.latexmkrc`
- literal `\input{...}` and `\include{...}` references, recursively
- literal `\addbibresource{...}` and `\bibliography{...}` references
- literal `\includegraphics{...}` references and literal `\graphicspath` lists
- input/include cycles, while allowing repeated non-cyclic input
- project-local package, class, and bibliography-style references
- the conventional `bib/` and `figures/` directories

Paths generated through TeX macros cannot be resolved safely by the MVP and
produce warnings. References that resolve outside the project, reference a
symbolic link, or name a missing file are errors. All matching references on
each line are checked. Escaped percent signs
(`\%`) are retained; only unescaped percent signs start comments. The check
is static and does not replace a real LaTeX build. Diagnostics for source
references include the project-relative filename and a one-based line number.
Supported literal command arguments and optional arguments may span lines;
diagnostics retain the command opening line. Graphicspath settings follow
explicit brace groups, `\begingroup` / `\endgroup`, and literal environments,
including groups that cross input-file boundaries. Macro-generated search paths
produce a warning instead of a false missing-figure error. This bounded scanner
does not evaluate macro definitions or conditionals. Symbolic links in any
reference path component are rejected.

`--json` writes only a JSON object to stdout, with `schema_version: 1`, numeric
`errors` and `warnings`, and a `diagnostics` array. Each diagnostic has `severity`
(`error` or `warning`), `message`, `file`, and `line`; project-wide diagnostics
have null file/line. It retains the usual exit status and requires no extra tool.

Missing optional conventional directories produce warnings. Missing required
project files or referenced files produce errors.

#### Exit Status

| Code | Meaning |
|---|---|
| `0` | No errors were found, with or without warnings |
| `1` | One or more errors were found |

---

## Global Options

### Help

Display command-line help.

```bash
kicho --help
kicho -h
kicho help
kicho help COMMAND
kicho COMMAND --help
kicho COMMAND -h
```

Calling `kicho` without a command also displays the help message.

`kicho help COMMAND` displays the command's summary, usage, examples, and
aliases when those fields are available. If a command does not define its own
usage text, Kicho displays a minimal default usage line.

The help command does not run the target command or check its runtime
requirements.

The command-specific `--help` and `-h` forms are equivalent to
`kicho help COMMAND`. They must also work when the current directory or external
tools do not satisfy the command's runtime requirements.

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
kicho 0.2.0-alpha.3
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

Normal command results and diagnostic reports from `doctor` and `check` are
written to standard output. Operational warnings from commands that create or
copy files are written to standard error.

User-facing errors should:

- state what failed
- avoid unnecessary implementation details
- suggest the relevant help command when appropriate

Example:

```text
Error: unknown command 'example'.
Run 'kicho --help' for usage.
```

Invalid arguments return status `1`. Commands that delegate to an external
program preserve that program's nonzero status where practical.

---

## Project Detection

In the current implementation, a directory is considered a Kicho project when it contains:

```text
.latexmkrc
```

This is intentionally a minimal rule.

A future release may introduce a general configuration format, potentially named:

```text
kicho.toml
```

Such a file could identify the project explicitly and store settings such as:

- the main TeX document
- the build directory
- project metadata
- archive behavior
- submission settings

General TOML configuration is deferred. The current literal `kicho.conf` path
settings are specified below.

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

For the default main document, the compiled PDF is therefore:

```text
build/main.pdf
```

The absence of `main.pdf` in the project root is expected. Editor integrations
should view `build/main.pdf` without changing the build destination.

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

## `archive` Command

Create a read-only snapshot of the current project.

```bash
kicho archive
```

The command requires a Kicho project and Python 3.9+ and does not accept
arguments. It creates:

```text
archives/YYYY-MM-DD_HH-MM-SS/
├── source/
├── pdf/
│   └── main.pdf
└── metadata/
    └── archive.json
```

The source snapshot copies the selected main file, `sections/`, `preamble/`,
`figures/`, `bib/`, and `.latexmkrc` when present, plus normalized path settings.
Missing source entries produce warnings
without failing the archive.

After copying, Kicho runs its static project check inside `source/`. If it
finds missing or invalid literal references, the archive is still retained,
but a warning includes the check report and explains that the snapshot may
not be self-contained. For example, a reference to `parts/result.tex` warns
if the referenced file was missing from the live source. This does not discover all TeX dependencies or
certify that the snapshot builds; custom styles and dynamic references still
require review.

If the selected PDF (default `build/main.pdf`) exists, it is copied to
`pdf/main.pdf`. A missing PDF
produces a warning and leaves the `pdf/` directory empty.

`archive.json` records the Kicho version, creation time, and project directory
name. When the project is inside a Git work tree with a valid `HEAD`, it also
records the branch (or `HEAD` when detached), commit, and dirty state. Kicho
only reads Git information and does not modify the repository.

Archive paths are never reused. The command fails if the timestamped destination
already exists. Creation is staged under the archive directory and published
only after all copies and metadata writes succeed. Failure or a handled
HUP/INT/TERM signal removes only staging files and the lock created by that invocation; an existing
snapshot is never changed. A symbolic-link archive directory is rejected.

---

## `split` Command

Split explicitly marked blocks from a project TeX source into `sections/*.tex`.

```text
kicho split [FILE]

% kicho:section introduction
Section contents.
% kicho:end
```

`FILE` defaults to `main.tex`. A specified file must be a relative `.tex` file
inside the project; absolute paths, parent-path components, and symbolic-link
sources are rejected.

The marker name must match `[a-z0-9][a-z0-9-]*`. Each opening marker must have
one closing marker, blocks cannot be nested, and names cannot be repeated.
Markers inside the known literal environments listed under `flatten` are ignored;
those examples are copied unchanged with their containing source block.

After a successful split, the marked block is replaced with:

```tex
\input{sections/introduction}
```

and its contents are written to `sections/introduction.tex`. Kicho validates all
markers and destinations before changing the project, refuses to overwrite an
existing section file, and saves the original beside the source file with a
`.kicho-backup` suffix. If a later copy fails, rollback removes every section
file created by that invocation, including a partially written current file,
and restores the source. Pre-existing section files are never removed.

---

## `flatten` Command

Create `dist/main.tex` without modifying the project source.

The command recursively expands `\input{...}` and `\include{...}` statements
that occupy a complete source line. A missing file, an include cycle, an
absolute path, or a path containing a `..` component is an error. `.tex` is
appended when the referenced path has no extension. Expanded `\include` commands
retain their leading and trailing `\clearpage` operations; `\input` expansion
does not add page breaks. TeX conditionals and per-include auxiliary checkpoints
remain outside the literal expansion contract.

Kicho refuses to overwrite an existing `dist/main.tex`, including a dangling
symbolic link, and rejects a symbolic-link `dist` directory.

Literal blocks in `verbatim`, `verbatim*`, `Verbatim`, `Verbatim*`,
`BVerbatim`, `LVerbatim`, `lstlisting`, and `minted` environments are copied
without expanding their contents. An unclosed literal block is an error.
Custom verbatim environments and arbitrary TeX macro parsing are unsupported.
The same protection applies to both submission modes. Literal masking preserves
active text before an opening delimiter and after a closing delimiter on the
same line, and supports delimiters whose command and argument span lines.
Dependency checking and cleaning use that same mask.

---

## `submit` Command

Create a local submission package without uploading it anywhere.

```text
kicho submit [--build] [--output DIRECTORY]
kicho submit --arxiv [--build] [--output DIRECTORY]
```

```text
submission/
├── main.tex
├── bib/
├── figures/
├── main.pdf          when build/main.pdf exists
├── .latexmkrc
└── manifest.json
```

`main.tex` is generated using the same expansion rules as `flatten`. Missing
optional files produce warnings. Kicho refuses to overwrite an existing
destination and does not modify source files or Git state. The default output
is `submission/`. `--output DIRECTORY` selects another relative directory
inside the project, for example `submissions/revision-2/`. Absolute paths,
parent (`..`) components, and paths that resolve outside the project through a
symbolic link are rejected. Kicho creates missing parent directories but never
overwrites the selected destination. Dependencies that collide with generated
root output names stop submission before publication: `main.tex` and `main.bbl`
for arXiv, and `main.tex`, `main.pdf`, `kicho.conf`, and `manifest.json` for standard
submission. The selected original main file is already represented by the
flattened output and is not copied over it. Rename a conflicting dependency
before submitting; Kicho does not rewrite its references. Reserved root filenames
are compared without ASCII case distinctions for portable exports.

`--build` runs `kicho build` before collecting the package and stops if the
build fails. It refreshes the working PDF, BBL, and recorder file without
editing the manuscript. Without this option, known source or configuration
files newer than an existing PDF/BBL cause a warning recommending `--build`.
Timestamp checks cannot certify freshness for arbitrary TeX macros.

### arXiv submission package

`kicho submit --arxiv` creates an arXiv upload archive and a separate metadata
worksheet in the selected output directory:

```text
submission/
├── arxiv-source.zip
├── arxiv-metadata.txt
└── manifest.json
```

The ZIP contains flattened `main.tex`, the selected compiled `.bbl` renamed to `main.bbl`,
the `figures/` directory, and project-local style/class dependencies, including
those in subdirectories. It does not contain `.bib` files, the built PDF, `.latexmkrc`, the manifest, the
metadata worksheet, or unreferenced hidden files from conventional figure copies.
Explicitly referenced hidden dependencies are retained. If the document uses a bibliography and
the selected compiled `.bbl` file is missing, the command fails and asks the user to build first.

When a project-root `arxiv-metadata.txt` exists, it is the user-maintained
source of truth and is copied unchanged. Otherwise Kicho creates a draft from
simple `\title`, `\author`, `abstract`, `\subjclass`, and `\keywords` forms in
the flattened source, saves that draft in the project root, and places a copy
beside the ZIP. Comments, inline verbatim examples, and known literal blocks
are excluded using the same active-source filter as dependency discovery.
Extraction is deliberately best-effort: fields that cannot be
read are marked for manual completion. Abstract text is bounded by its opening
and closing delimiters even when both occur on one line; an unclosed abstract
is marked for manual completion instead of absorbing subsequent body text.
Kicho warns about incomplete fields,
non-ASCII characters, and abstracts over 1920 characters. The metadata file is
not part of the arXiv upload archive.

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


### Dependency preservation and literal examples

Archives additionally copy statically resolved project-local input, bibliography,
figure, package, class, and bibliography-style dependencies, preserving relative
paths (including `parts/` and `styles/`). Local styles are scanned recursively.
A matching project-root recorder file (default `build/main.fls`) additionally supplies compiler-recorded
project-local dependencies, excluding generated auxiliary files. External TeX
installation files are not copied. `kicho build` explicitly enables the recorder.
Stale recorder files for another project root are ignored with a warning.
Submission packages also retain referenced input and figure files, so inline
input commands that flatten does not expand remain usable. arXiv packages still
exclude bibliography databases and require the compiled bibliography for active
bibliography commands. Missing or unsafe dependencies stop submission; archives
retain available sources and report missing dependencies as warnings.
Commented commands, inline `\verb` / `\verb*` examples, and known literal
blocks are ignored when discovering references and bibliography usage.


## Project paths, build diagnostics, and provenance

`kicho.conf` is an optional UTF-8 project-root file with literal `key = value`
lines. Supported keys are `main` (default `main.tex`) and `build_dir` (default
`build`). Empty lines and full-line `#` comments are allowed. Values are unquoted
relative paths; internal spaces are allowed and quote characters are literal.
Normalized command-line and environment paths with leading or trailing
whitespace are rejected so saved configurations preserve the same path.
Unknown or duplicate keys, empty values,
absolute paths, parent components, and symlink path components are errors.
The main path must end in `.tex`; the build directory must not be the project
root, a source ancestor, or a reserved Kicho/Git output directory.

Precedence is command-line `--main FILE` / `--build-dir DIR`, then environment
`KICHO_MAIN` / `KICHO_BUILD_DIR`, then `kicho.conf`, then defaults. Global options
precede the command. These settings apply to existing-project commands; `init`
retains the selected template's default layout. They do not change TeX engine
selection. Direct editor builds and Git-ignore rules must be adjusted separately
when custom paths are chosen; Kicho does not rewrite those files. `build` and `clean` pass the selected main, output, and auxiliary
directory explicitly to latexmk. The output stem is the main filename without
`.tex`; customized latexmk job names are outside this path contract.

`check`, `flatten`, `split` (when FILE is omitted), `archive`, and `submit`
use the selected main file. Flattening and submission retain canonical
`main.tex` output names. Standard submissions contain a normalized `kicho.conf`
so they build independently with `kicho build`; archives retain the selected
paths and a normalized configuration alongside the original sources.

The static source scanner processes supported commands in source order,
including multiple graphicspath declarations and image/input commands on one
line. Repeated inputs are scanned in their current path context. This remains
a literal scanner; it does not evaluate arbitrary TeX macros or conditionals.

`doctor` additionally reports Python 3.9+ (paragraph IDs, submissions and
provenance) and `zip` (arXiv packaging). Archives also require Python for provenance. Missing optional capabilities produce
warnings, retaining the existing core LaTeX failure rules.

`build [--strict]` summarizes undefined citation/reference warnings from the
selected TeX log after a successful latexmk run. `--strict` returns failure when
those warnings remain. `check --log [--json]` combines static diagnostics with
warnings from that log without compiling. Missing logs and logs older than
known inputs are warnings; strict builds fail if a fresh log is unavailable.
This diagnostic summary never verifies mathematical correctness.

arXiv ZIPs include explicitly referenced hidden project files. Unreferenced
hidden files from bulk figure copies are excluded before dependencies are
copied; needed files are never silently removed by ZIP patterns. Fast tests
inspect archive contents, while real-template smoke tests extract arXiv ZIPs
and compile only their exported sources, including compiled bibliographies.

Archive and submission metadata have `schema_version: 2`, retain the existing
fields, and add `tools` and `files`. `files` maps package-relative regular-file
paths to SHA-256 digests; `tools` records available TeX tool versions, with null
for missing or unavailable version probes. Versions describe the tools available
at export time, not necessarily those that produced a previously copied PDF. Metadata itself is excluded from the digest map. These are
artifact provenance records, not proof-validation records. arXiv manifests
also contain a `source_files` digest map for the uncompressed ZIP entries.
