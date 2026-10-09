"""Regression cases for diagnostics, portable exports, and failed snapshots."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class Exports(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "日本語 Paper With Spaces"
        self.root.mkdir()
        (self.root / ".latexmkrc").write_text("test configuration\n")
        (self.root / "main.tex").write_text("\\documentclass{article}\nBody.\n")
        for name in ("bib", "figures", "build"):
            (self.root / name).mkdir()

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def cli(self, *args, env=None):
        return subprocess.run([os.environ.get("KICHO_TEST_BASH", "/bin/bash"),
                               str(ROOT / "bin/kicho"), *args], cwd=self.root,
                              env=env, capture_output=True, text=True, timeout=30)

    def fake(self, name, script):
        directory = Path(self.temp.name) / "fake-bin"
        directory.mkdir(exist_ok=True)
        command = directory / name
        command.write_text("#!/bin/bash\n" + script)
        command.chmod(0o755)
        return dict(os.environ, PATH=str(directory) + os.pathsep + os.environ["PATH"])

    def builder(self, status=0):
        return self.fake("latexmk", """[[ "$1" == -recorder ]] || exit 91
mkdir -p build
printf FRESH-PDF > build/main.pdf
printf FRESH-BBL > build/main.bbl
printf 'PWD %s\\nINPUT main.tex\\n' "$PWD" > build/main.fls
""" + f"exit {status}\n")

    def test_hidden_dependencies_are_kept_but_unreferenced_hidden_figures_are_not(self):
        self.write("main.tex", "Before \\input{.parts/body} after.\n"
                   "\\includegraphics{figures/.required.pdf}\n")
        self.write(".parts/body.tex", "Needed hidden source.\n")
        self.write("figures/.required.pdf", "Needed hidden figure.")
        self.write("figures/.private/token", "Not a dependency.")
        result = self.cli("submit", "--arxiv")
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.root / "submission/arxiv-source.zip") as archive:
            self.assertEqual(archive.read(".parts/body.tex"), b"Needed hidden source.\n")
            self.assertEqual(archive.read("figures/.required.pdf"), b"Needed hidden figure.")
            self.assertNotIn("figures/.private/token", archive.namelist())
            self.assertIn(r"\input{.parts/body}", archive.read("main.tex").decode())

    def test_commands_are_checked_in_order_and_repeated_inputs_use_current_paths(self):
        self.write("first/one.pdf", "FIRST")
        self.write("second/two.pdf", "SECOND")
        self.write("main.tex", r"\graphicspath{{first/}}\includegraphics{one}"
                   r"\graphicspath{{second/}}\includegraphics{two}" + "\n")
        result = self.cli("check", "--json")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["errors"], 0)
        self.write("main.tex", r"\graphicspath{{first/}}\graphicspath{{second/}}"
                   r"\includegraphics{two}" + "\n")
        self.assertEqual(self.cli("check").returncode, 0)
        self.write("first/plot.pdf", "ONE")
        self.write("second/plot.pdf", "TWO")
        self.write("parts/repeated.tex", r"\includegraphics{plot}" + "\n")
        self.write("main.tex", r"\graphicspath{{first/}}\input{parts/repeated}"
                   r"\graphicspath{{second/}}\input{parts/repeated}" + "\n")
        result = self.cli("submit")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "submission/first/plot.pdf").read_text(), "ONE")
        self.assertEqual((self.root / "submission/second/plot.pdf").read_text(), "TWO")

    def test_log_diagnostics_preserve_static_errors_and_locations(self):
        self.write("main.tex", "\\input{missing}\n")
        self.write("build/main.log", "LaTeX Warning: Citation `unknown' on page 1 undefined on input line 5.\n\n"
                   "LaTeX Warning: Reference `thm' on page 1\nundefined on input line 8.\n\n"
                   "LaTeX Warning: There were undefined references.\n\n")
        result = self.cli("check", "--log", "--json")
        self.assertEqual(result.returncode, 1, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual((data["errors"], data["warnings"]), (1, 2))
        self.assertEqual(data["diagnostics"][0]["file"], "main.tex")
        self.assertEqual(data["diagnostics"][1]["file"], "build/main.log")
        self.assertEqual(data["diagnostics"][1]["line"], 1)
        self.assertIn("undefined", data["diagnostics"][2]["message"])
        os.utime(self.root / "build/main.log", (1000, 1000))
        result = self.cli("check", "--json", "--log")
        self.assertIn("stale", result.stdout)
        (self.root / "build/main.log").unlink()
        self.assertIn("unavailable", self.cli("check", "--log", "--json").stdout)

    def test_strict_build_fails_only_for_unresolved_or_unavailable_logs(self):
        script = r'''if [[ "$1" == -v ]]; then printf 'Fake latexmk 1\n'; exit 0; fi
mkdir -p build
printf '%s\n\n' "LaTeX Warning: Citation 'missing' undefined on input line 1." > build/main.log
'''
        env = self.fake("latexmk", script)
        self.assertEqual(self.cli("build", env=env).returncode, 0)
        result = self.cli("build", "--strict", env=env)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Citation", result.stdout)
        self.assertIn("strict build", result.stderr)
        env = self.fake("latexmk", "mkdir -p build\nprintf 'Output written.\\n' > build/main.log\n")
        self.assertEqual(self.cli("build", "--strict", env=env).returncode, 0)
        (self.root / "build/main.log").unlink()
        env = self.fake("latexmk", "exit 0\n")
        self.assertEqual(self.cli("build", "--strict", env=env).returncode, 1)

    def test_project_paths_precedence_and_exports_use_custom_outputs(self):
        self.write("kicho.conf", "# Literal configuration\nmain = 原稿 paper.tex\nbuild_dir = output files\n")
        self.write("原稿 paper.tex", "Configured document.\n")
        self.write("output files/原稿 paper.pdf", "CUSTOM PDF")
        self.write("output files/原稿 paper.bbl", "CUSTOM BBL")
        self.write("data/extra.dat", "RECORDED")
        self.write("output files/原稿 paper.fls", f"PWD {self.root}\nINPUT data/extra.dat\n")
        result = self.cli("check", "--json")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.cli("flatten").returncode, 0)
        self.assertIn("Configured", (self.root / "dist/main.tex").read_text())
        result = self.cli("submit")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "submission/main.pdf").read_text(), "CUSTOM PDF")
        self.assertEqual((self.root / "submission/data/extra.dat").read_text(), "RECORDED")
        self.assertEqual((self.root / "submission/kicho.conf").read_text(), "main = main.tex\nbuild_dir = build\n")
        result = self.cli("submit", "--arxiv", "--output", "arxiv-custom")
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.root / "arxiv-custom/arxiv-source.zip") as archive:
            self.assertEqual(archive.read("main.bbl"), b"CUSTOM BBL")
        result = self.cli("archive")
        self.assertEqual(result.returncode, 0, result.stderr)
        snapshot = next(path for path in (self.root / "archives").iterdir() if not path.name.startswith('.'))
        self.assertEqual((snapshot / "source/原稿 paper.tex").read_text(), "Configured document.\n")
        self.assertEqual((snapshot / "pdf/main.pdf").read_text(), "CUSTOM PDF")
        env = dict(os.environ, KICHO_MAIN="missing.tex")
        self.assertEqual(self.cli("check", "--json", env=env).returncode, 1)
        result = self.cli("--main", "原稿 paper.tex", "check", "--json", env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        env = self.fake("latexmk", 'printf "%s\\n" "$@" > called-args\nexit 0\n')
        result = self.cli("--build-dir", "different output", "build", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        arguments = (self.root / "called-args").read_text().splitlines()
        self.assertIn("-outdir=different output", arguments)
        self.assertIn("-auxdir=different output", arguments)
        self.assertEqual(arguments[-1], "原稿 paper.tex")
        env = dict(os.environ, KICHO_MAIN="main.tex")
        result = self.cli("check", "--json", env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_invalid_paths_are_rejected_and_clean_preserves_authored_sources(self):
        for text in ("main = ../outside.tex\n", "build_dir = .\n", "build_dir = ././\n",
                     "build_dir = /tmp/out\n", "build_dir = archives/x\n",
                     "main = build/paper.tex\n", "other = value\n",
                     "main = main.tex\nmain = other.tex\n", "main =\n"):
            self.write("kicho.conf", text)
            self.assertNotEqual(self.cli("check").returncode, 0, text)
        (self.root / "kicho.conf").unlink()
        (self.root / "linked").symlink_to(Path(self.temp.name), target_is_directory=True)
        self.assertNotEqual(self.cli("--build-dir", "linked/out", "build").returncode, 0)
        self.write("build/authored.tex", "PRESERVE")
        result = self.cli("clean", env=self.fake("latexmk", "exit 0\n"))
        self.assertEqual(result.returncode, 1)
        self.assertEqual((self.root / "build/authored.tex").read_text(), "PRESERVE")
        self.assertIn("contains source files", result.stderr)

    def test_clean_protects_referenced_figures_and_recorded_data(self):
        env = self.fake("latexmk", "touch called-clean\nexit 0\n")
        for name, source, recorder in (
                ("build/original.pdf", "\\includegraphics{build/original.pdf}\n", ""),
                ("build/input.csv", "Body.\n", f"PWD {self.root}\nINPUT build/input.csv\n")):
            with self.subTest(name=name):
                self.write(name, "ORIGINAL")
                self.write("main.tex", source)
                self.write("build/main.fls", recorder)
                result = self.cli("clean", env=env)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertFalse((self.root / "called-clean").exists())
                self.assertEqual((self.root / name).read_text(), "ORIGINAL")

    def test_clean_preserves_unknown_files_and_populated_caches(self):
        names = ("build/notes.md", "build/data.csv", "build/texmf-var/cache.dat")
        for name in names:
            self.write(name, "PRESERVE")
        self.write("build/main.aux", "GENERATED")
        result = self.cli("clean", env=self.fake("latexmk", "rm -f build/main.aux\n"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "build/main.aux").exists())
        for name in names:
            self.assertEqual((self.root / name).read_text(), "PRESERVE")
        self.assertIn("Retained", result.stdout)

    def test_clean_removes_only_empty_build_directories(self):
        (self.root / "build/texmf-var/empty").mkdir(parents=True)
        result = self.cli("clean", env=self.fake("latexmk", "exit 0\n"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "build").exists())

    def test_multiline_dependencies_are_exported_without_recorder(self):
        self.write("main.tex", "\\documentclass\n{classes/local}\n"
                   "\\usepackage[\nexample=true\n]\n{styles/local}\n"
                   "\\includegraphics*\n[width=2mm]\n{assets/plot}\n"
                   "\\input\n{parts/body}\n\\bibliography\n{bib/references}\n")
        files = {"classes/local.cls": "\\LoadClass{article}\n",
                 "styles/local.sty": "\\input\n{data/style-body}\n",
                 "data/style-body.tex": "STYLE BODY", "parts/body.tex": "BODY",
                 "assets/plot.pdf": "FIGURE"}
        for name, text in files.items():
            self.write(name, text)
        self.write("bib/references.bib", "BIBLIOGRAPHY")
        self.write("build/main.bbl", "COMPILED BIBLIOGRAPHY")
        result = self.cli("check", "--json")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["warnings"], 0)
        result = self.cli("submit")
        self.assertEqual(result.returncode, 0, result.stderr)
        for name, text in files.items():
            self.assertEqual((self.root / 'submission' / name).read_text(), text)
        result = self.cli("submit", "--arxiv", "--output", "arxiv-export")
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.root / "arxiv-export/arxiv-source.zip") as archive:
            for name, text in files.items():
                self.assertEqual(archive.read(name).decode(), text)
            self.assertEqual(archive.read('main.bbl'), b'COMPILED BIBLIOGRAPHY')

    def test_multiline_missing_reference_uses_command_opening_line(self):
        self.write("main.tex", "Body.\n\\includegraphics\n[width=2mm]\n{assets/missing}\n")
        result = self.cli("check", "--json")
        self.assertEqual(result.returncode, 1, result.stderr)
        record = json.loads(result.stdout)["diagnostics"][0]
        self.assertEqual((record["file"], record["line"]), ("main.tex", 2))

    def test_graphicspath_restores_nested_groups_and_environments(self):
        self.write("outer images/one.pdf", "OUTER")
        self.write("inner/two.pdf", "INNER")
        self.write("deep/three.pdf", "DEEP")
        for opening, closing in (("{", "}"), ("\\begingroup", "\\endgroup"),
                                 ("\\begin{minipage}", "\\end{minipage}")):
            with self.subTest(opening=opening):
                self.write("main.tex", "\\graphicspath{{outer images/}}\n" + opening +
                           "\\graphicspath{{inner/}}\\includegraphics{two}\n"
                           "{\\graphicspath{{deep/}}\\includegraphics{three}}\n"
                           "\\includegraphics{two}" + closing + "\\includegraphics{one}\n")
                result = self.cli("check", "--json")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.cli("submit", "--arxiv")
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.root / "submission/arxiv-source.zip") as archive:
            self.assertEqual(archive.read("outer images/one.pdf"), b"OUTER")
            self.assertEqual(archive.read("inner/two.pdf"), b"INNER")
            self.assertEqual(archive.read("deep/three.pdf"), b"DEEP")

    def test_groups_cross_inputs_and_restore_dynamic_search_state(self):
        self.write("outer/one.pdf", "OUTER")
        self.write("inner/two.pdf", "INNER")
        self.write("parts/open.tex", "{\\graphicspath{{inner/}}\n")
        self.write("parts/close.tex", "}\n")
        self.write("main.tex", "\\graphicspath{{outer/}}\\input{parts/open}"
                   "\\includegraphics{two}\\input{parts/close}\\includegraphics{one}\n"
                   "{\\graphicspath{\\unknown}\\includegraphics{unknown}}"
                   "\\includegraphics{one}\n")
        result = self.cli("check", "--json")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["errors"], 0)
        self.assertGreaterEqual(json.loads(result.stdout)["warnings"], 2)

    def test_directory_symlinks_are_rejected_without_publication(self):
        source = self.write("data/body.tex", "LIVE BODY")
        (self.root / "alias").symlink_to('data', target_is_directory=True)
        self.write("main.tex", "\\input{alias/body}\n")
        for args in (("check", "--json"), ("flatten",), ("submit",), ("submit", "--arxiv")):
            result = self.cli(*args)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("symbolic", result.stdout + result.stderr)
        self.assertEqual(source.read_text(), "LIVE BODY")
        self.assertFalse((self.root / 'submission').exists())
        self.assertFalse((self.root / 'dist/main.tex').exists())

    def test_arxiv_rejects_a_linked_figure_directory(self):
        self.write("data/body.tex", "LIVE BODY")
        (self.root / "figures").rmdir()
        (self.root / "figures").symlink_to('data', target_is_directory=True)
        self.write("main.tex", "Before \\input{figures/body} after.\n")
        result = self.cli('submit', '--arxiv')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('symbolic link', result.stderr)
        self.assertFalse((self.root / 'submission').exists())
        self.assertFalse((self.root / 'arxiv-metadata.txt').exists())

    def test_metadata_ignores_comments_inline_examples_and_literal_blocks(self):
        self.write("main.tex", r'''\title{Actual \% title}
% \title{Old title}
\author{Correct Author}
% \author{Discarded Author}
Example: \verb|\title{Example title}|.
\begin{verbatim}
\author{Example Author}
\title{Literal title}
\end{verbatim}
\begin{abstract}
Actual abstract. % discarded note
\end{abstract}
''')
        result = self.cli('submit', '--arxiv')
        self.assertEqual(result.returncode, 0, result.stderr)
        metadata = (self.root / 'arxiv-metadata.txt').read_text()
        self.assertIn('Actual \\% title', metadata)
        self.assertIn('Correct Author', metadata)
        self.assertIn('Actual abstract.', metadata)
        for ignored in ('Old title', 'Discarded Author', 'Example title', 'Example Author',
                        'Literal title', 'discarded note'):
            self.assertNotIn(ignored, metadata)
        self.write('arxiv-metadata.txt', 'OWNER MAINTAINED\n')
        result = self.cli('submit', '--arxiv', '--output', 'second-arxiv')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'second-arxiv/arxiv-metadata.txt').read_text(),
                         'OWNER MAINTAINED\n')

    def test_unserializable_outer_whitespace_is_rejected_before_writes(self):
        self.write(' paper.tex', 'LIVE SOURCE')
        env = self.fake('latexmk', 'touch called-build\nexit 0\n')
        for args in (('--main', ' paper.tex', 'archive'),
                     ('--main', './ paper.tex', 'archive'),
                     ('--build-dir', 'output ', 'build'),
                     ('--build-dir', './ output', 'build')):
            result = self.cli(*args, env=env)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('whitespace', result.stderr)
        for key, value in (('KICHO_MAIN', ' paper.tex'), ('KICHO_BUILD_DIR', ' output')):
            result = self.cli('archive', env=dict(os.environ, **{key: value}))
            self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'archives').exists())
        self.assertFalse((self.root / 'called-build').exists())
        self.assertEqual((self.root / ' paper.tex').read_text(), 'LIVE SOURCE')

    def test_archive_internal_spaces_round_trip_without_option_overrides(self):
        self.write('draft/ paper.tex', 'ARCHIVED SOURCE')
        result = self.cli('--main', 'draft/ paper.tex', '--build-dir', 'output files', 'archive')
        self.assertEqual(result.returncode, 0, result.stderr)
        source = next((self.root / 'archives').glob('*/source'))
        self.assertEqual((source / 'draft/ paper.tex').read_text(), 'ARCHIVED SOURCE')
        result = subprocess.run(['/bin/bash', str(ROOT / 'bin/kicho'), 'check', '--json'],
                                cwd=source, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_manifest_hashes_cover_final_files_and_do_not_touch_the_live_pdf(self):
        self.write("build/main.pdf", "ORIGINAL PDF")
        before = (self.root / "build/main.pdf").read_bytes()
        result = self.cli("submit")
        self.assertEqual(result.returncode, 0, result.stderr)
        package = self.root / "submission"
        data = json.loads((package / "manifest.json").read_text())
        self.assertEqual(data["schema_version"], 2)
        self.assertIn("latexmk", data["tools"])
        self.assertNotIn("manifest.json", data["files"])
        for name, digest in data["files"].items():
            self.assertEqual(hashlib.sha256((package / name).read_bytes()).hexdigest(), digest)
        self.assertEqual((self.root / "build/main.pdf").read_bytes(), before)
        result = self.cli("submit", "--arxiv", "--output", "hashed-arxiv")
        self.assertEqual(result.returncode, 0, result.stderr)
        package = self.root / "hashed-arxiv"
        data = json.loads((package / "manifest.json").read_text())
        with zipfile.ZipFile(package / "arxiv-source.zip") as archive:
            expected = {name for name in archive.namelist() if not name.endswith('/')}
            self.assertEqual(set(data["source_files"]), expected)
            for name, digest in data["source_files"].items():
                self.assertEqual(hashlib.sha256(archive.read(name)).hexdigest(), digest)
        result = self.cli("archive")
        self.assertEqual(result.returncode, 0, result.stderr)
        snapshot = next(path for path in (self.root / "archives").iterdir() if not path.name.startswith('.'))
        data = json.loads((snapshot / "metadata/archive.json").read_text())
        self.assertIn("source/main.tex", data["files"])
        self.assertIn("pdf/main.pdf", data["files"])
        for name, digest in data["files"].items():
            self.assertEqual(hashlib.sha256((snapshot / name).read_bytes()).hexdigest(), digest)

    def test_missing_python_stops_before_build_or_export_writes(self):
        env = self.fake("python3", "exit 1\n")
        for args in (("archive",), ("submit", "--build"), ("submit", "--arxiv")):
            result = self.cli(*args, env=env)
            self.assertEqual(result.returncode, 1)
            self.assertIn("Python 3.9", result.stderr)
            self.assertFalse((self.root / "archives").exists())
            self.assertFalse((self.root / "submission").exists())
            self.assertFalse((self.root / "build/main.pdf").exists())

    def test_submission_interrupt_cleans_owned_temporary_files(self):
        temp = Path(self.temp.name) / "staging"
        temp.mkdir()
        env = self.fake("cp", 'kill -TERM "$PPID"\nexit 1\n')
        env['TMPDIR'] = str(temp)
        result = self.cli("submit", env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "submission").exists())
        self.assertFalse(any(path.name.startswith("kicho-") for path in temp.iterdir()))
        result = self.cli("submit", "--arxiv", env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(path.name.startswith("kicho-") for path in temp.iterdir()))

    def assert_no_archive(self):
        archives = self.root / "archives"
        self.assertFalse(archives.exists() and list(archives.iterdir()))

    def test_cycles_have_locations_but_repeated_inputs_are_allowed(self):
        self.write("main.tex", "\\input{parts/a}\n")
        self.write("parts/a.tex", "\\input{parts/b}\n")
        self.write("parts/b.tex", "Text.\n\\input{parts/a}\n")
        result = self.cli("check", "--json")
        self.assertEqual(result.returncode, 1, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["schema_version"], 1)
        self.assertEqual(data["errors"], 1)
        diagnostic = data["diagnostics"][0]
        self.assertEqual((diagnostic["file"], diagnostic["line"]), ("parts/b.tex", 2))
        self.assertIn("cycle", diagnostic["message"])
        self.assertEqual(result.stderr, "")
        self.assertIn("parts/b.tex:2:", self.cli("check").stdout)
        self.write("parts/b.tex", "A result.\n")
        self.write("main.tex", "\\input{parts/a}\n\\input{parts/a}\n")
        result = self.cli("check", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["errors"], 0)

    def test_json_escapes_unicode_and_warns_without_errors(self):
        self.write("parts/日本語.tex", '\\input{missing "引用"}\n')
        self.write("main.tex", "\\input{parts/日本語}\n")
        result = self.cli("check", "--json")
        self.assertEqual(result.returncode, 1)
        record = json.loads(result.stdout)["diagnostics"][0]
        self.assertEqual(record["file"], "parts/日本語.tex")
        self.assertIn('missing "引用"', record["message"])
        self.write("main.tex", "\\input{\\jobname}\n")
        result = self.cli("check", "--json")
        self.assertEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual((data["errors"], data["warnings"]), (0, 1))
        self.assertEqual(data["diagnostics"][0]["severity"], "warning")
        self.assertNotEqual(self.cli("check", "--json", "--json").returncode, 0)
        (self.root / ".latexmkrc").unlink()
        data = json.loads(self.cli("check", "--json").stdout)
        self.assertIsNone(data["diagnostics"][0]["file"])
        self.assertIsNone(data["diagnostics"][0]["line"])

    def test_literal_graphicspath_across_lines_and_in_an_input(self):
        self.write("preamble/graphics.tex", "\\graphicspath{\n{absent/}\n{figures/}\n}\n")
        self.write("main.tex", "\\input{preamble/graphics}\n\\includegraphics{plot}\n")
        self.write("figures/plot.pdf", "FIGURE")
        result = self.cli("check", "--json")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(json.loads(result.stdout)["errors"], 0)
        self.write("main.tex", "\\graphicspath{{figures/}}\n\\includegraphics{plot}\n")
        self.assertEqual(self.cli("check").returncode, 0)
        result = self.cli("submit")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "submission/figures/plot.pdf").read_text(), "FIGURE")

    def test_dynamic_graphicspath_is_a_warning_not_a_missing_figure_error(self):
        self.write("main.tex", "\\graphicspath{\\imagepaths}\n\\includegraphics{plot}\n")
        result = self.cli("check", "--json")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["errors"], 0)
        self.assertGreaterEqual(data["warnings"], 1)

    def test_local_styles_classes_and_nested_inputs_are_preserved(self):
        self.write("main.tex", "\\documentclass{classes/local}\n\\usepackage{styles/front}\n")
        self.write("classes/local.cls", "\\LoadClass{article}\n")
        self.write("styles/front.sty", "\\RequirePackage{styles/nested}\n")
        self.write("styles/nested.sty", "\\input{data/fragment}\n")
        self.write("data/fragment.tex", "Portable fragment.\n")
        result = self.cli("submit")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.cli("submit", "--arxiv", "--output", "arxiv-export")
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = ("classes/local.cls", "styles/front.sty", "styles/nested.sty", "data/fragment.tex")
        with zipfile.ZipFile(self.root / "arxiv-export/arxiv-source.zip") as archive:
            for name in expected:
                self.assertEqual(archive.read(name), (self.root / name).read_bytes())
                self.assertEqual((self.root / "submission" / name).read_bytes(), (self.root / name).read_bytes())
        self.write("main.tex", "\\usepackage{styles/absent}\n")
        result = self.cli("submit", "--output", "missing-style")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "missing-style").exists())

    def test_recorder_preserves_dynamic_local_inputs_and_omits_system_and_aux_files(self):
        self.write("data/recorded.dat", "RECORDED")
        self.write("build/main.aux", "AUXILIARY")
        outside = Path(self.temp.name) / "system.sty"
        outside.write_text("SYSTEM")
        self.write("build/main.fls", f"PWD {self.root}\nINPUT data/recorded.dat\n"
                   f"INPUT {outside}\nINPUT build/main.aux\n")
        result = self.cli("submit")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "submission/data/recorded.dat").read_text(), "RECORDED")
        self.assertFalse((self.root / "submission/system.sty").exists())
        self.assertFalse((self.root / "submission/build/main.aux").exists())
        result = self.cli("submit", "--arxiv", "--output", "recorded-arxiv")
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.root / "recorded-arxiv/arxiv-source.zip") as archive:
            self.assertEqual(archive.read("data/recorded.dat"), b"RECORDED")
            self.assertNotIn("build/main.aux", archive.namelist())
        self.write("build/main.fls", f"PWD {self.temp.name}\nINPUT data/recorded.dat\n")
        result = self.cli("submit", "--output", "moved-project")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("another project root", result.stderr)
        self.assertFalse((self.root / "moved-project/data/recorded.dat").exists())

    def test_recorder_cannot_copy_through_a_symlink_or_change_the_live_source(self):
        source = self.write("data/local.sty", "LIVE SOURCE")
        (self.root / "figures/alias").symlink_to(source.parent, target_is_directory=True)
        self.write("build/main.fls", f"PWD {self.root}\nINPUT figures/alias/local.sty\n")
        result = self.cli("submit")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symbolic link", result.stderr)
        self.assertFalse((self.root / "submission").exists())
        self.assertEqual(source.read_text(), "LIVE SOURCE")

    def test_stale_pdf_and_bbl_warn_and_build_refreshes_both_modes(self):
        self.write("main.tex", "\\bibliography{bib/references}\n")
        self.write("bib/references.bib", "@book{example,title={Example}}\n")
        for name in ("build/main.pdf", "build/main.bbl"):
            path = self.write(name, "OLD OUTPUT")
            os.utime(path, (1000, 1000))
        result = self.cli("submit")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("may be stale", result.stderr)
        result = self.cli("submit", "--arxiv", "--output", "old-arxiv")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("build/main.bbl", result.stderr)
        env = self.builder()
        result = self.cli("submit", "--build", "--output", "fresh-standard", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("may be stale", result.stderr)
        self.assertEqual((self.root / "fresh-standard/main.pdf").read_text(), "FRESH-PDF")
        result = self.cli("submit", "--arxiv", "--build", "--output", "fresh-arxiv", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.root / "fresh-arxiv/arxiv-source.zip") as archive:
            self.assertEqual(archive.read("main.bbl"), b"FRESH-BBL")
            self.assertNotIn("bib/references.bib", archive.namelist())
        self.assertNotEqual(self.cli("submit", "--build", "--build", env=env).returncode, 0)

    def test_failed_build_does_not_publish_or_modify_the_manuscript(self):
        source = (self.root / "main.tex").read_bytes()
        result = self.cli("submit", "--build", env=self.builder(status=7))
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertFalse((self.root / "submission").exists())
        self.assertEqual((self.root / "main.tex").read_bytes(), source)

    def test_archive_copy_and_publication_failures_leave_no_partial_snapshot(self):
        for name in ("cp", "mv"):
            result = self.cli("archive", env=self.fake(name, "exit 73\n"))
            self.assertNotEqual(result.returncode, 0)
            self.assert_no_archive()
            (Path(self.temp.name) / "fake-bin" / name).unlink()
        self.assertEqual((self.root / "main.tex").read_text(), "\\documentclass{article}\nBody.\n")

    def test_archive_metadata_failure_and_interrupt_clean_staging(self):
        env = self.fake("cp", """destination="${@: -1}"
if [[ "$destination" == */source ]]; then
    rm -rf -- "$destination/../metadata"
    : > "$destination/../metadata"
fi
exec /bin/cp "$@"
""")
        self.assertNotEqual(self.cli("archive", env=env).returncode, 0)
        self.assert_no_archive()
        env = self.fake("cp", 'kill -TERM "$PPID"\nexit 1\n')
        self.assertNotEqual(self.cli("archive", env=env).returncode, 0)
        self.assert_no_archive()

    def test_archive_collision_and_symlink_directory_preserve_existing_files(self):
        snapshot = self.root / "archives/2026-01-01_00-00-00"
        snapshot.mkdir(parents=True)
        marker = snapshot / "keep.txt"
        marker.write_text("EXISTING")
        env = self.fake("date", """if [[ "$1" == '+%Y-%m-%d_%H-%M-%S' ]]; then
    printf '2026-01-01_00-00-00\\n'
else
    exec /bin/date "$@"
fi
""")
        result = self.cli("archive", env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(marker.read_text(), "EXISTING")
        other = Path(self.temp.name) / "Symlink Paper"
        other.mkdir()
        (other / ".latexmkrc").write_text("config")
        (other / "main.tex").write_text("source")
        outside = Path(self.temp.name) / "external-archives"
        outside.mkdir()
        (other / "archives").symlink_to(outside, target_is_directory=True)
        self.root = other
        result = self.cli("archive")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(outside.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
