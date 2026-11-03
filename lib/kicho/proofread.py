#!/usr/bin/env python3
"""Literal proofreading corrections with explicit, backed-up author approval."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys
import tempfile
import uuid

sys.dont_write_bytecode = True
from paraids import TOKEN, SKIP, group, is_kicho_export, visible_source

ID = re.compile(r"r-[0-9a-f]{12}\Z")
COMMANDS = {"kichoadd": "add", "kichodelete": "delete", "kichoreplace": "replace"}
SUFFIXES = {".tex", ".sty", ".cls", ".ltx"}


@dataclass
class Correction:
    id: str
    kind: str
    start: int
    end: int
    line: int
    old: str
    new: str


def corrections(text: str) -> list[Correction]:
    """Read literal commands using masked offsets, retaining original arguments."""
    clean = visible_source(text)
    found = []
    for token in TOKEN.finditer(clean):
        if token[1] not in COMMANDS:
            continue
        if found and token.start() < found[-1].end:
            raise ValueError("nested proofreading corrections are unsupported")
        kind = COMMANDS[token[1]]
        position = token.end()
        arguments = []
        for _ in range(3 if kind == "replace" else 2):
            start, position = group(clean, position)
            arguments.append((start, position))
        first, end = arguments[0]
        identifier = clean[first + 1:end - 1]
        if not ID.fullmatch(identifier):
            raise ValueError(f"invalid proofreading ID {identifier!r}")
        contents = [text[start + 1:end - 1] for start, end in arguments[1:]]
        old = contents[0] if kind in {"delete", "replace"} else ""
        new = contents[-1] if kind in {"add", "replace"} else ""
        found.append(Correction(identifier, kind, token.start(), position,
                                text.count("\n", 0, token.start()) + 1, old, new))
    return found


def safe_root(root: Path) -> Path:
    root = root.absolute()
    # macOS exposes /tmp and /var through system-owned aliases.
    for part in (root, *root.parents):
        if part.is_symlink() and part not in {Path("/tmp"), Path("/var")}:
            raise ValueError(f"refusing symbolic-link root: {part}")
    if not root.is_dir():
        raise ValueError("root must be an existing manuscript directory")
    return root.resolve()


def sources(root: Path, *, staged: bool = False, build_dir: str | None = None):
    # Staging already contains only selected dependencies: even a source under
    # build/ or a manifest-identified directory must be validated there.
    skip = set() if staged else set(SKIP)
    # A configured output directory is generated, even if it is not named build.
    config = root / "kicho.conf"
    if build_dir is None and config.is_file() and not config.is_symlink() and not staged:
        for line in config.read_text(encoding="utf-8").splitlines():
            key, sep, value = line.partition("=")
            if sep and key.strip() == "build_dir":
                build_dir = value.strip()
    if build_dir is not None and not staged:
        selected = Path(build_dir)
        if not build_dir.strip() or selected.is_absolute() or ".." in selected.parts or selected == Path("."):
            raise ValueError("build directory must be a nonempty relative path without '..'")
        skip.add(selected.as_posix())
    for directory, names, files in os.walk(root, followlinks=False):
        base = Path(directory)
        names[:] = sorted(name for name in names
                          if name not in skip
                          and (base / name).relative_to(root).as_posix() not in skip
                          and not (base / name).is_symlink()
                          and (staged or not is_kicho_export(base / name)))
        for name in sorted(files):
            path = base / name
            if path.suffix not in SUFFIXES or name == "kichoproof.sty":
                continue
            if path.is_symlink() or not path.is_file():
                raise ValueError(f"refusing symbolic-link or nonregular source: {path}")
            yield path


def scan(root: Path, *, staged: bool = False, build_dir: str | None = None):
    result = []
    seen = {}
    for path in sources(root, staged=staged, build_dir=build_dir):
        raw = path.read_bytes()
        # Ordinary non-UTF-8 styles without proofreading commands need no parser.
        if not any(name.encode() in raw for name in COMMANDS):
            continue
        try:
            text = raw.decode("utf-8")
            entries = corrections(text)
            for entry in entries:
                if entry.id in seen:
                    raise ValueError(f"duplicate proofreading ID {entry.id}; first seen in {seen[entry.id]}")
                seen[entry.id] = path.relative_to(root)
        except (UnicodeError, ValueError) as error:
            raise ValueError(f"{path.relative_to(root)}: {error}") from error
        result.append((path, raw, text, entries))
    return result


def ensure_approved(root: Path) -> None:
    """Submission gate: validate the exact staged inputs before stripping styles."""
    pending = [(path, entry) for path, _, _, entries in scan(root, staged=True) for entry in entries]
    if pending:
        path, entry = pending[0]
        raise ValueError(f"pending proofreading correction {entry.id} in {path.relative_to(root)}:{entry.line}; "
                         "record author approval with kicho proofread approve, then rebuild")


def install(root: Path) -> None:
    source = Path(__file__).resolve().parent / "latex/kichoproof.sty"
    target = root / source.name
    data = source.read_bytes()
    if target.is_symlink():
        raise ValueError("refusing symbolic-link package destination")
    if target.exists():
        if target.is_file() and target.read_bytes() == data:
            print(f"Already current: {target}")
            return
        raise ValueError("existing package differs; preserve local changes before updating")
    with target.open("xb") as output:
        output.write(data)
    print(f"Installed: {target}")


def new(root: Path, kind: str, old: str | None, new_text: str | None,
        build_dir: str | None = None) -> None:
    if (kind in {"delete", "replace"}) != (old is not None):
        raise ValueError("--old is required only for delete and replace")
    if (kind in {"add", "replace"}) != (new_text is not None):
        raise ValueError("--new is required only for add and replace")
    reserved = set()
    for path in sources(root, build_dir=build_dir):
        text = path.read_text(encoding="utf-8")
        reserved.update(re.findall(r"r-[0-9a-f]{12}\b", visible_source(text, include_comments=True)))
    identifier = "r-" + secrets.token_hex(6)
    while identifier in reserved:
        identifier = "r-" + secrets.token_hex(6)
    arguments = [identifier]
    if old is not None:
        arguments.append(old)
    if new_text is not None:
        arguments.append(new_text)
    snippet = "\\kicho" + kind + "".join("{" + arg + "}" for arg in arguments)
    parsed = corrections(snippet)
    if len(parsed) != 1 or parsed[0].end != len(snippet):
        raise ValueError("correction text must have balanced literal LaTeX arguments")
    print(snippet)


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def atomic_write(path: Path, data: bytes, mode: int) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=".kicho-proofread-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
            os.fchmod(output.fileno(), mode)
        if path.is_symlink():
            raise ValueError(f"source became a symbolic link: {path}")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def approve(root: Path, identifiers: list[str], all_ids: bool, author: str,
            build_dir: str | None = None) -> None:
    if not author.strip():
        raise ValueError("--author must be nonempty")
    if bool(identifiers) == all_ids:
        raise ValueError("approve requires either IDs or --all")
    if len(set(identifiers)) != len(identifiers):
        raise ValueError("duplicate requested approval ID")
    scanned = scan(root, build_dir=build_dir)
    available = {entry.id for _, _, _, entries in scanned for entry in entries}
    selected = available if all_ids else set(identifiers)
    unknown = selected - available
    if unknown:
        raise ValueError("unknown proofreading ID: " + ", ".join(sorted(unknown)))
    if not selected:
        raise ValueError("no pending proofreading corrections to approve")
    changes, records = [], []
    for path, before, text, entries in scanned:
        approved = [entry for entry in entries if entry.id in selected]
        if not approved:
            continue
        after = text
        for entry in reversed(approved):
            # Keep the argument's TeX scope and lexical boundaries. Even an
            # empty deletion group prevents \\LaTeX + book becoming \\LaTeXbook.
            accepted = "{" + entry.new + "}"
            after = after[:entry.start] + accepted + after[entry.end:]
        changes.append((path, before, after.encode("utf-8"), stat.S_IMODE(path.stat().st_mode)))
        for entry in approved:
            records.append({"id": entry.id, "kind": entry.kind, "path": path.relative_to(root).as_posix(),
                            "line": entry.line, "old": entry.old, "new": entry.new})
    history = root / "archives/proofread"
    for directory in (root / "archives", history):
        if directory.is_symlink():
            raise ValueError(f"refusing symbolic-link history: {directory}")
        directory.mkdir(exist_ok=True)
    lock = history / ".approve-lock"
    try:
        lock.mkdir()
    except FileExistsError as error:
        raise ValueError("another approval is in progress; inspect archives/proofread/.approve-lock") from error
    saved = None
    applied = []
    manifest = None
    try:
        now = datetime.now(timezone.utc)
        saved = history / (now.strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex[:12])
        saved.mkdir()
        manifest = {"schema_version": 1, "author": author, "created_at": now.isoformat(),
                    "status": "prepared", "corrections": records, "files": []}
        for path, before, after, _ in changes:
            relative = path.relative_to(root)
            backup = saved / "before" / relative
            backup.parent.mkdir(parents=True, exist_ok=True)
            with backup.open("xb") as output:
                output.write(before)
            manifest["files"].append({"path": relative.as_posix(), "before_sha256": sha256(before),
                                      "after_sha256": sha256(after)})
        manifest_path = saved / "manifest.json"
        atomic_write(manifest_path, (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode(), 0o644)
        # All originals are preserved before changing any manuscript file.
        for path, before, after, mode in changes:
            if path.is_symlink() or path.read_bytes() != before:
                raise ValueError(f"source changed during approval: {path}")
            atomic_write(path, after, mode)
            applied.append((path, before, after, mode))
        manifest["status"] = "approved"
        atomic_write(manifest_path, (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode(), 0o644)
    except (OSError, ValueError):
        for path, before, after, mode in reversed(applied):
            if not path.is_symlink() and path.read_bytes() == after:
                atomic_write(path, before, mode)
        if manifest is not None and saved is not None:
            manifest["status"] = "rolled-back"
            atomic_write(saved / "manifest.json",
                         (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode(), 0o644)
        raise
    finally:
        lock.rmdir()
    print(f"Approved {len(selected)} correction(s) by {author}.")
    print(f"History: {saved.relative_to(root)}")
    print("Run kicho build to refresh the PDF.")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    for action in ("install", "new", "list", "check", "approve", "prepare-release"):
        command = sub.add_parser(action)
        command.add_argument("--root", type=Path, default=Path.cwd())
        command.add_argument("--build-dir", help=argparse.SUPPRESS)
        if action == "new":
            command.add_argument("--kind", choices=["add", "delete", "replace"], required=True)
            command.add_argument("--old")
            command.add_argument("--new")
        elif action == "approve":
            command.add_argument("identifiers", nargs="*")
            command.add_argument("--all", action="store_true")
            command.add_argument("--author", required=True)
    args = parser.parse_args(argv)
    try:
        root = safe_root(args.root)
        if args.action == "install":
            install(root)
        elif args.action == "new":
            new(root, args.kind, args.old, args.new, args.build_dir)
        elif args.action == "approve":
            approve(root, args.identifiers, args.all, args.author, args.build_dir)
        elif args.action == "prepare-release":
            ensure_approved(root)
        else:
            entries = [(path, entry) for path, _, _, found in scan(root, build_dir=args.build_dir) for entry in found]
            for path, entry in entries:
                print(f"{path.relative_to(root)}:{entry.line}: {entry.id} {entry.kind} pending")
            if args.action == "check":
                print(f"Proofreading checks passed; {len(entries)} pending correction(s).")
        return 0
    except (OSError, ValueError, UnicodeError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
