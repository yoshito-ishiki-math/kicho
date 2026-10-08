"""One offline suite for package ownership, ID handling, and submission cleanup."""
import contextlib
import hashlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "lib/kicho"))
import paraids


class ParagraphIDs(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "Paper With Spaces"
        self.root.mkdir()

    def cli(self, *args, env=None):
        return subprocess.run([os.environ.get("KICHO_TEST_BASH", "/bin/bash"),
                               str(ROOT / "bin/kicho"), *args], cwd=self.root,
                              env=env, capture_output=True, text=True)

    def project(self):
        (self.root / ".latexmkrc").write_text("test configuration\n")
        (self.root / "main.tex").write_text(r"""\documentclass{article}
\usepackage{amsmath,paragraphids,showkeys}
\usepackage{custom}
\setlength\paragraphnotewidth{25mm}
\renewcommand*{\paragraphidfont}{\tiny}
\begin{document}
\paraid{p-111111111111}
\paranote[12pt]{7}{A note with {nested} text.

Another line.}
First paragraph.

\input{body} Second paragraph.
\end{document}
""")
        (self.root / "body.tex").write_text("\\paraid{p-222222222222} Body text.\n")
        (self.root / "custom.sty").write_text("\\ProvidesPackage{custom}\n\\RequirePackage{showkeys}\n")
        (self.root / "build").mkdir()
        (self.root / "build/main.pdf").write_bytes(b"ANNOTATED WORKING PDF")
        result = self.cli("paraids", "install")
        self.assertEqual(result.returncode, 0, result.stderr)

    def snapshot(self):
        return {str(p.relative_to(self.root)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in self.root.rglob("*") if p.is_file()}

    def fake_builder(self, status=0):
        directory = Path(self.temp.name) / "bin"
        directory.mkdir()
        command = directory / "latexmk"
        command.write_text("#!/bin/sh\nmkdir -p build\nprintf CLEAN-REBUILT-PDF > build/main.pdf\n"
                           + f"exit {status}\n")
        command.chmod(0o755)
        return dict(os.environ, PATH=str(directory) + os.pathsep + os.environ["PATH"])

    def test_install_generation_and_search_do_not_rewrite_sources(self):
        source = self.root / "main.tex"
        source.write_text("% \\paraid{p-111111111111}\n\\paraid{p-222222222222}\nText.\n")
        before = source.read_bytes()
        result = self.cli("paraids", "install", str(self.root))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "paragraphids.sty").exists())
        for _ in range(2):
            result = self.cli("paraids", "install")
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "paragraphids.sty").read_bytes(),
                         (ROOT / "lib/kicho/latex/paragraphids.sty").read_bytes())
        with patch.object(paraids.secrets, "token_hex", side_effect=["111111111111", "222222222222", "333333333333"]):
            stream = io.StringIO()
            with contextlib.redirect_stdout(stream):
                self.assertEqual(paraids.main(["new", "--root", str(self.root)]), 0)
            self.assertEqual(stream.getvalue().strip(), r"\paraid{p-333333333333}")
        self.assertEqual(self.cli("paraids", "check").returncode, 0)
        self.assertEqual(self.cli("paraids", "find", "p-111111111111").returncode, 1)
        self.assertEqual(self.cli("paraids", "find", "p-111111111111", "--include-comments").returncode, 0)
        self.assertEqual(source.read_bytes(), before)
        (self.root / "paragraphids.sty").write_text("local customization")
        self.assertNotEqual(self.cli("paraids", "install").returncode, 0)
        self.assertEqual((self.root / "paragraphids.sty").read_text(), "local customization")
        (self.root / "paragraphids.sty").unlink()
        (self.root / "paragraphids.sty").symlink_to(source)
        self.assertNotEqual(self.cli("paraids", "install").returncode, 0)
        self.assertEqual(source.read_bytes(), before)

    def test_literal_examples_and_duplicate_checks(self):
        source = self.root / "main.tex"
        source.write_text(r"""\verb|\paraid{p-111111111111}|
\begin{Verbatim*}
\paraid{p-111111111111}
\end{Verbatim*}
\\paraid{p-111111111111}
% \paraid{p-333333333333}
\paraid{p-222222222222}
Text.
""")
        self.assertEqual([x[0] for x in paraids.occurrences(source)], ["p-222222222222"])
        self.assertEqual(self.cli("paraids", "check").returncode, 0)
        with source.open("a") as stream:
            stream.write("\\paraid{p-222222222222}\n\\paraid{invalid}\n")
        result = self.cli("paraids", "check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DUPLICATE", result.stdout)
        self.assertIn("INVALID", result.stdout)

    def test_cleanup_is_complete_idempotent_and_preserves_body_boundaries(self):
        source = r"""\usepackage[show]{paragraphids}
\PassOptionsToPackage{show}{paragraphids}
\RequirePackage{amsmath,showkeys}
\setlength{\paragraphidwidth}{19mm}
\renewcommand*\paragraphnotefont{\small}
\global\long\def\paragraphidfont{\tiny}
\ParagraphIDsOff
% \paraid{p-333333333333}
\paraid{p-111111111111}
\paranote[8pt]{2}{First {part}.

Last part.}
First paragraph.

\paraid{p-222222222222} Second paragraph.
\verb|\paraid{example}|
\begin{verbatim}
\paranote{1}{Literal text.}
\end{verbatim}
"""
        result = paraids.release_source(source)
        self.assertEqual(paraids.release_source(result), result)
        self.assertEqual(list(paraids.editorial_spans(result)), [])
        self.assertIn(r"\RequirePackage{amsmath}", result)
        self.assertNotIn(r"\global", paraids.visible_source(result))
        self.assertIn("First paragraph.\n\n% \\paraid{p-222222222222}\n Second paragraph.", result)
        self.assertNotIn("\n\nFirst paragraph", result)
        self.assertIn("% \\paraid{p-333333333333}", result)
        self.assertNotIn("% %", result)
        self.assertIn("\\begin{verbatim}\n\\paranote{1}{Literal text.}\n\\end{verbatim}", result)
        self.assertEqual(paraids.release_source("\\paraid{p-111111111111}   \nBody.\n"),
                         "% \\paraid{p-111111111111}   \nBody.\n")

    def test_bad_cleanup_never_partially_rewrites_files(self):
        (self.root / "main.tex").write_text("\\usepackage{paragraphids}\n")
        for bad in ["\\paranote{1}{Unclosed\n", "\\paragraphidwidth=19mm\n"]:
            (self.root / "z.tex").write_text(bad)
            before = self.snapshot()
            with self.assertRaises(ValueError):
                paraids.prepare_release(self.root)
            self.assertEqual(before, self.snapshot())

    def test_both_submissions_clean_all_sources_and_archive_keeps_marks(self):
        self.project()
        original = self.snapshot()
        result = self.cli("archive")
        self.assertEqual(result.returncode, 0, result.stderr)
        archive = next((self.root / "archives").glob("*/source"))
        self.assertEqual((archive / "paragraphids.sty").read_bytes(), (self.root / "paragraphids.sty").read_bytes())
        self.assertEqual((archive / "main.tex").read_bytes(), (self.root / "main.tex").read_bytes())
        result = self.cli("submit", "--arxiv", "--output", "arxiv-export")
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.root / "arxiv-export/arxiv-source.zip") as archive:
            self.assertNotIn("paragraphids.sty", archive.namelist())
            for name in ("main.tex", "body.tex", "custom.sty"):
                self.assertEqual(list(paraids.editorial_spans(archive.read(name).decode())), [])
            self.assertIn("Body text.", archive.read("body.tex").decode())
        result = self.cli("submit", "--output", "standard-export", env=self.fake_builder())
        self.assertEqual(result.returncode, 0, result.stderr)
        exported = self.root / "standard-export"
        self.assertEqual((exported / "main.pdf").read_bytes(), b"CLEAN-REBUILT-PDF")
        self.assertFalse((exported / "paragraphids.sty").exists())
        self.assertFalse((exported / "build").exists())
        for name, value in original.items():
            self.assertEqual(hashlib.sha256((self.root / name).read_bytes()).hexdigest(), value, name)

    def test_failed_release_build_and_malformed_marks_do_not_publish(self):
        self.project()
        original = self.snapshot()
        result = self.cli("submit", env=self.fake_builder(status=7))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "submission").exists())
        self.assertEqual(self.snapshot(), original)
        (self.root / "body.tex").write_text("\\paranote{1}{Unclosed\n")
        original = self.snapshot()
        result = self.cli("submit", "--arxiv")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "submission").exists())
        self.assertEqual(self.snapshot(), original)


if __name__ == "__main__":
    unittest.main()
