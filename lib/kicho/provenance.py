"""Append artifact hashes and installed TeX tool versions to a Kicho manifest."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def hashes(root, excluded=None):
    result = {}
    for directory, names, files in os.walk(root, followlinks=False):
        names[:] = sorted(name for name in names
                          if not (Path(directory) / name).is_symlink())
        for name in sorted(files):
            path = Path(directory) / name
            if path == excluded or path.is_symlink() or not path.is_file():
                continue
            digest = hashlib.sha256()
            with path.open('rb') as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b''):
                    digest.update(chunk)
            result[path.relative_to(root).as_posix()] = digest.hexdigest()
    return dict(sorted(result.items()))


def tool_versions():
    result = {}
    # Version probes must never read or write the working project's files.
    with tempfile.TemporaryDirectory(prefix='kicho-tool-versions-') as directory:
        for tool, flag in (('latexmk', '-v'), ('lualatex', '--version'),
                           ('pdflatex', '--version'), ('xelatex', '--version'),
                           ('biber', '--version')):
            result[tool] = None
            if shutil.which(tool) is None:
                continue
            try:
                process = subprocess.run([tool, flag], capture_output=True, text=True,
                                         errors='replace', timeout=5, cwd=directory)
                if process.returncode == 0:
                    lines = (process.stdout + process.stderr).strip().splitlines()
                    result[tool] = lines[0][:512] if lines else None
            except (OSError, subprocess.TimeoutExpired):
                pass
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--sources', type=Path)
    args = parser.parse_args()
    if args.manifest.is_symlink():
        parser.error('manifest must not be a symbolic link')
    root = args.root.resolve(strict=True)
    manifest = args.manifest.resolve(strict=True)
    manifest.relative_to(root)
    record = json.loads(manifest.read_text(encoding='utf-8'))
    record['schema_version'] = 2
    record['files'] = hashes(root, manifest)
    if args.sources is not None:
        record['source_files'] = hashes(args.sources.resolve(strict=True))
    record['tools'] = tool_versions()
    manifest.write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n',
                        encoding='utf-8')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        print(f'Error: could not record artifact provenance: {error}', file=sys.stderr)
        sys.exit(1)
