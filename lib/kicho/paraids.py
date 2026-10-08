#!/usr/bin/env python3
"""Manage Kicho's paragraph-ID package and prepare editorial marks for release."""
from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import sys
from pathlib import Path

ID = re.compile(r"p-[0-9a-f]{12}\Z")
LITERAL = {"verbatim", "verbatim*", "Verbatim", "Verbatim*", "BVerbatim", "LVerbatim", "lstlisting", "minted", "comment"}
SKIP = {".git", "build", "dist", "output", "archives", "submission", "submissions",
        ".venv", ".uv-cache", "__pycache__"}
TOKEN = re.compile(r"\\([A-Za-z@]+|.)", re.S)
SETTINGS = {"paragraphidfont", "paragraphidwidth", "paragraphnotefont", "paragraphnotewidth"}
MARKS = {"paraid", "paranote", "ParagraphIDsOn", "ParagraphIDsOff"}
PACKAGES = {"paragraphids", "showkeys"}


def visible_source(text: str, include_comments: bool = False) -> str:
    """Blank comments and common literal environments, preserving offsets."""
    chars = list(text)
    i = 0
    while i < len(text):
        end = i
        if text[i] == "%":
            end = text.find("\n", i)
            if end < 0:
                end = len(text)
            if include_comments:
                i = end
                continue
        elif text[i] == "\\":
            env = re.match(r"\\begin\s*\{([^}]+)\}", text[i:])
            verb = re.match(r"\\verb\*?(?![A-Za-z])", text[i:])
            if env and env[1] in LITERAL:
                close = re.search(r"\\end\s*\{" + re.escape(env[1]) + r"\}", text[i + env.end():])
                end = len(text) if close is None else i + env.end() + close.end()
            elif verb and i + verb.end() < len(text):
                start = i + verb.end()
                close = text.find(text[start], start + 1)
                end = len(text) if close < 0 else close + 1
            else:
                # Consume escaped % and other control symbols as a unit.
                token = re.match(r"\\(?:[A-Za-z@]+|.)", text[i:])
                i += token.end() if token else 1
                continue
        if end > i:
            for j in range(i, end):
                if chars[j] != "\n":
                    chars[j] = " "
            i = end
        else:
            i += 1
    return "".join(chars)


def is_kicho_export(directory: Path) -> bool:
    manifest = directory / "manifest.json"
    if manifest.is_symlink():
        return False
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    return (isinstance(data, dict) and isinstance(data.get("kicho_version"), str)
            and isinstance(data.get("project"), str))


def manuscript_files(root: Path):
    if root.is_file():
        return [root]
    paths = []
    for directory, names, files in os.walk(root, followlinks=False):
        base = Path(directory)
        names[:] = sorted(name for name in names if name not in SKIP
                          and not (base / name).is_symlink()
                          and not is_kicho_export(base / name))
        paths.extend(base / name for name in sorted(files) if name.endswith(".tex"))
    return sorted(paths)


def occurrences(root: Path, include_comments: bool = False):
    paths = manuscript_files(root)
    for path in paths:
        relative = path.relative_to(root) if root.is_dir() else Path(path.name)
        if any(part in SKIP for part in relative.parts) or path.is_symlink():
            continue
        text = path.read_text(encoding="utf-8")
        clean = visible_source(text, include_comments)
        for token in TOKEN.finditer(clean):
            if token[1] != "paraid":
                continue
            match = re.match(r"\s*\{([^{}]*)\}", clean[token.end():])
            if match:
                yield match[1], path, text.count("\n", 0, token.start()) + 1


def install(root: Path) -> None:
    if not root.is_dir():
        raise ValueError("install requires an existing manuscript directory")
    source = Path(__file__).resolve().parent / "latex" / "paragraphids.sty"
    target = root / source.name
    data = source.read_bytes()
    if target.is_symlink():
        raise ValueError("refusing a symlink package destination")
    if target.exists():
        if target.is_file() and target.read_bytes() == data:
            print(f"Already current: {target}")
            return
        raise ValueError("existing package differs; inspect and preserve local changes before updating")
    with target.open("xb") as output:
        output.write(data)
    print(f"Installed: {target}")


def skip_space(text: str, position: int) -> int:
    while position < len(text) and text[position].isspace():
        position += 1
    return position


def group(text: str, position: int, opening: str = "{"):
    """Read one literal balanced argument from masked source, retaining offsets."""
    position = skip_space(text, position)
    if position >= len(text) or text[position] != opening:
        raise ValueError("expected a literal balanced argument")
    closing = "}" if opening == "{" else "]"
    start = position
    depth = 1
    braces = 0
    position += 1
    while position < len(text):
        if text[position] == "\\":
            token = TOKEN.match(text, position)
            position = token.end() if token else position + 1
            continue
        char = text[position]
        if opening == "[" and char == "{":
            braces += 1
        elif opening == "[" and char == "}":
            braces -= 1
        elif braces == 0 and char == opening:
            depth += 1
        elif braces == 0 and char == closing:
            depth -= 1
            if depth == 0:
                return start, position + 1
        position += 1
    raise ValueError("unclosed editorial command argument")


def optional_group(text: str, position: int):
    start = skip_space(text, position)
    return group(text, start, "[") if text[start:start + 1] == "[" else (position, position)


def target_command(text: str, position: int):
    position = skip_space(text, position)
    if text[position:position + 1] == "{":
        start, end = group(text, position)
        token = TOKEN.fullmatch(text[start + 1:end - 1].strip())
        return (token[1] if token else ""), end
    token = TOKEN.match(text, position)
    return (token[1], token.end()) if token else ("", position)


def editorial_spans(text: str):
    """Yield whole commands to comment, and any unrelated package replacement."""
    clean = visible_source(text)
    covered = 0
    for token in TOKEN.finditer(clean):
        if token.start() < covered:
            continue
        name = token[1]
        end = token.end()
        replacement = ""
        if name in {"paraid", "paranote"}:
            if name == "paranote":
                _, end = optional_group(clean, end)
                _, end = group(clean, end)
            _, end = group(clean, end)
        elif name in {"ParagraphIDsOn", "ParagraphIDsOff"}:
            pass
        elif name in {"usepackage", "RequirePackage", "RequirePackageWithOptions", "PassOptionsToPackage"}:
            if name == "PassOptionsToPackage":
                _, option_end = group(clean, end)
            else:
                _, option_end = optional_group(clean, end)
            start, package_end = group(clean, option_end)
            packages = clean[start + 1:package_end - 1].split(",")
            if not any(Path(p.strip()).stem in PACKAGES for p in packages):
                continue
            kept = [p.strip() for p in packages if p.strip() and Path(p.strip()).stem not in PACKAGES]
            _, end = optional_group(clean, package_end)
            if kept:
                replacement = (clean[token.start():start] + "{" + ",".join(kept) + "}"
                               + clean[package_end:end])
        elif name in {"setlength", "addtolength", "newlength"}:
            target, end = target_command(clean, end)
            if target not in SETTINGS:
                continue
            if name != "newlength":
                _, end = group(clean, end)
        elif name in {"renewcommand", "newcommand", "providecommand", "DeclareRobustCommand"}:
            if clean[end:end + 1] == "*":
                end += 1
            target, end = target_command(clean, end)
            if target not in SETTINGS:
                continue
            _, end = optional_group(clean, end)
            _, end = optional_group(clean, end)
            _, end = group(clean, end)
        elif name in {"def", "gdef", "edef", "xdef"}:
            target, end = target_command(clean, end)
            if target not in SETTINGS:
                continue
            _, end = group(clean, end)
        elif name in SETTINGS or name.startswith("paragraphids@"):
            raise ValueError(f"unsupported setting \\{name}; use a separate setlength/renewcommand command")
        else:
            continue
        start = token.start()
        prefix = re.search(r"(?:\\(?:global|long|protected|outer)\s*)+$", clean[:start])
        if prefix:
            start = prefix.start()
        covered = end
        yield start, end, replacement


def release_source(text: str) -> str:
    """Comment literal editorial commands without introducing blank paragraphs."""
    spans = list(editorial_spans(text))
    output = []
    cursor = 0
    for start, end, replacement in spans:
        # Reuse the existing line ending when only whitespace/comment follows.
        # Adding a second newline here would create a new TeX paragraph.
        eol = text.find("\n", end)
        if eol < 0:
            eol = len(text)
        if not visible_source(text[end:eol]).strip():
            end = eol
        raw = text[start:end]
        commented = "\n".join(line if line.lstrip().startswith("%") else "% " + line
                              for line in raw.split("\n"))
        output.append(text[cursor:start])
        output.append(commented)
        if replacement:
            output.append("\n" + replacement)
        if end < len(text) and text[end] != "\n":
            output.append("\n")
        cursor = end
    output.append(text[cursor:])
    result = "".join(output)
    if list(editorial_spans(result)):
        raise ValueError("active editorial command remains after release preparation")
    return result


def has_review_material(text: str) -> bool:
    # Commented markers may have been disabled after the working PDF was built.
    clean = visible_source(text, include_comments=True)
    return (any(t[1] in MARKS | SETTINGS for t in TOKEN.finditer(clean))
            or bool(re.search(r"\b(?:paragraphids|showkeys)\b", clean)))


def prepare_release(root: Path) -> bool:
    """Internal submit operation, applied only to an already-created staging copy."""
    if not root.is_dir() or not (root / "main.tex").is_file():
        raise ValueError("release preparation requires a staging directory with main.tex")
    changes = []
    packages = []
    review = False
    for path in sorted(root.rglob("*")):
        if path.suffix not in {".tex", ".sty", ".cls", ".ltx"}:
            continue
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError(f"refusing a symlink release source: {path}")
        if path.name in {"paragraphids.sty", "showkeys.sty"}:
            packages.append(path)
            continue
        raw = path.read_bytes()
        if not re.search(rb"paragraphid|paragraphnote|ParagraphIDs|\\paraid|\\paranote|showkeys", raw):
            continue
        text = raw.decode("utf-8")
        review = review or has_review_material(text)
        try:
            result = release_source(text)
        except ValueError as error:
            raise ValueError(f"{path.relative_to(root)}: {error}") from error
        if result != text:
            changes.append((path, result.encode("utf-8")))
    # Validate every file before changing even the staging copy.
    for path, data in changes:
        path.write_bytes(data)
    for path in packages:
        path.unlink()
    return review


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["install", "new", "check", "find", "prepare-release"])
    parser.add_argument("identifier", nargs="?")
    parser.add_argument("--root", type=Path)
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--include-comments", action="store_true",
                        help="include commented tags in find/check; new always reserves them")
    args = parser.parse_args(argv)
    if args.action != "find" and args.identifier:
        parser.error("only find accepts a positional ID; use --root for the manuscript path")
    if args.action == "prepare-release" and args.root is None:
        parser.error("internal release preparation requires an explicit staging --root")
    if args.root is None:
        args.root = Path.cwd()
    if not args.root.exists():
        parser.error("--root does not exist")
    if args.action == "install":
        install(args.root)
        return 0
    if args.action == "prepare-release":
        print("review" if prepare_release(args.root) else "plain")
        return 0
    if args.action == "find" and not args.identifier:
        parser.error("find requires an ID")
    if args.count < 1:
        parser.error("--count must be positive")
    rows = list(occurrences(args.root, args.action == "new" or args.include_comments))
    if args.action == "new":
        used = {row[0] for row in rows}
        for _ in range(args.count):
            while (value := "p-" + secrets.token_hex(6)) in used:
                pass
            used.add(value)
            print("\\paraid{" + value + "}")
        return 0
    if args.action == "find":
        found = [row for row in rows if row[0] == args.identifier]
        for value, path, line in found:
            print(f"{path}:{line}: {value}")
        return 0 if found else 1
    seen = {}
    errors = 0
    for value, path, line in rows:
        if not ID.fullmatch(value):
            print(f"INVALID {path}:{line}: {value}")
            errors += 1
        elif value in seen:
            print(f"DUPLICATE {path}:{line}: {value}; first at {seen[value]}")
            errors += 1
        else:
            seen[value] = f"{path}:{line}"
    print(f"{len(rows)} marker(s), {errors} error(s).")
    return int(errors > 0)


if __name__ == "__main__":
    try:
        if sys.version_info < (3, 9):
            raise ValueError("paragraph-ID operations require Python 3.9 or later")
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(1)
