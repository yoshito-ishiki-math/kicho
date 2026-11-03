"""Offline workflow checks for tracked corrections and explicit author approval."""
import contextlib
import hashlib
import importlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "lib/kicho"))


class Proofreading(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="kicho-proofread-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "日本語 Paper With Spaces"
        self.root.mkdir()

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data if isinstance(data, bytes) else data.encode("utf-8"))
        return path

    def cli(self, *args, env=None):
        return subprocess.run([os.environ.get("KICHO_TEST_BASH", "/bin/bash"),
                               str(ROOT / "bin/kicho"), *args], cwd=self.root,
                              env=env, capture_output=True, text=True, timeout=30)

    def succeeds(self, *args, env=None):
        result = self.cli(*args, env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes()
                for p in self.root.rglob("*") if p.is_file() and not p.is_symlink()}

    def manifests(self):
        return list((self.root / "archives/proofread").glob("*/manifest.json"))

    def project(self):
        self.write(".latexmkrc", "$pdf_mode = 1;\n")
        self.write("main.tex", r"""\documentclass{article}
\usepackage{kichoproof}
\begin{document}
Before \kichoreplace{r-111111111111}{old wording}{new wording} after.
\input{parts/body}
\end{document}
""")
        self.write("parts/body.tex", "\\kichoadd{r-222222222222}{Added body.}\n")
        self.write("build/main.pdf", b"STALE-RED-WORKING-PDF")
        (self.root / "bib").mkdir()
        (self.root / "figures").mkdir()
        self.succeeds("proofread", "install")

    def fake_builder(self):
        directory = Path(self.temp.name) / "bin"
        directory.mkdir()
        command = directory / "latexmk"
        command.write_text("#!/bin/sh\nmkdir -p build\nprintf FRESH-ACCEPTED-PDF > build/main.pdf\n")
        command.chmod(0o755)
        return dict(os.environ, PATH=str(directory) + os.pathsep + os.environ["PATH"])

    def test_install_is_opt_in_idempotent_and_preserves_custom_packages(self):
        source = self.write("main.tex", b"UNCHANGED MANUSCRIPT\r\n")
        self.succeeds("proofread", "install")
        package = self.root / "kichoproof.sty"
        self.assertEqual(package.read_bytes(), (ROOT / "lib/kicho/latex/kichoproof.sty").read_bytes())
        self.succeeds("proofread", "install")
        self.assertEqual(source.read_bytes(), b"UNCHANGED MANUSCRIPT\r\n")
        package.write_text("local customization")
        self.assertNotEqual(self.cli("proofread", "install").returncode, 0)
        self.assertEqual(package.read_text(), "local customization")
        package.unlink()
        package.symlink_to(source)
        self.assertNotEqual(self.cli("proofread", "install").returncode, 0)
        self.assertEqual(source.read_bytes(), b"UNCHANGED MANUSCRIPT\r\n")

    def test_new_prints_snippets_without_editing_and_reserves_commented_ids(self):
        self.write("main.tex", "% \\kichoadd{r-111111111111}{historical}\n"
                   "\\kichoadd{r-222222222222}{pending}\n")
        before = self.snapshot()
        proofread = importlib.import_module("proofread")
        with patch.object(proofread.secrets, "token_hex", side_effect=["111111111111", "222222222222", "333333333333"]):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(proofread.main(["new", "--kind", "replace", "--old", "古い {語}",
                                                 "--new", "新しい $x^2$", "--root", str(self.root)]), 0)
        self.assertEqual(output.getvalue().strip(),
                         r"\kichoreplace{r-333333333333}{古い {語}}{新しい $x^2$}")
        self.assertEqual(before, self.snapshot())
        for kind, option, text, macro in (("add", "--new", "new", "kichoadd"),
                                          ("delete", "--old", "old", "kichodelete")):
            result = self.succeeds("proofread", "new", "--kind", kind, option, text)
            self.assertRegex(result.stdout.strip(), r"^\\" + macro + r"\{r-[0-9a-f]{12}\}\{" + text + r"\}$")
        for args in (("new", "--kind", "replace", "--new", "only one side"),
                     ("new", "--kind", "add", "--new", "unclosed {")):
            self.assertNotEqual(self.cli("proofread", *args).returncode, 0)

    def test_list_check_ignore_examples_and_history_without_mutating_sources(self):
        self.write("main.tex", r"""% \kichoadd{r-111111111111}{comment}
\verb|\kichoadd{r-111111111111}{literal}|
\begin{Verbatim*}
\kichoadd{r-111111111111}{literal}
\end{Verbatim*}
\\kichoadd{r-111111111111}{escaped command}
Text \kichoadd{r-222222222222}{A \% and {nested} text.}
""")
        for directory in ("archives/old", "build", "submission", "submissions/old", "dist"):
            self.write(directory + "/main.tex", r"\kichoadd{r-222222222222}{historical duplicate}")
        self.write("custom-export/manifest.json", json.dumps({"kicho_version": "test", "project": "test"}))
        self.write("custom-export/main.tex", r"\kichoadd{r-222222222222}{export duplicate}")
        before = self.snapshot()
        result = self.succeeds("proofread", "list")
        self.assertIn("r-222222222222", result.stdout)
        self.assertIn("main.tex", result.stdout)
        self.assertIn("add", result.stdout)
        self.assertNotIn("r-111111111111", result.stdout)
        self.succeeds("proofread", "check")
        self.assertEqual(before, self.snapshot())

    def test_individual_approval_preserves_other_marks_and_exact_bytes_with_audit(self):
        original = ("Prefix \\kichoreplace{r-111111111111}{old {word}}"
                    "{New \\textbf{word} and \\% sign.} suffix.\r\n"
                    "\\kichoadd{r-222222222222}{Unapproved.}\r\n").encode()
        source = self.write("parts/body.tex", original)
        expected = ("Prefix {New \\textbf{word} and \\% sign.} suffix.\r\n"
                    "\\kichoadd{r-222222222222}{Unapproved.}\r\n").encode()
        self.succeeds("proofread", "approve", "r-111111111111", "--author", "伊敷喜斗")
        self.assertEqual(source.read_bytes(), expected)
        self.assertEqual(len(self.manifests()), 1)
        manifest_path = self.manifests()[0]
        self.assertEqual((manifest_path.parent / "before/parts/body.tex").read_bytes(), original)
        manifest = json.loads(manifest_path.read_text())
        audit = json.dumps(manifest, ensure_ascii=False)
        for value in ("伊敷喜斗", "r-111111111111", "old {word}",
                      hashlib.sha256(original).hexdigest(), hashlib.sha256(expected).hexdigest()):
            self.assertIn(value, audit)
        self.assertRegex(audit, r"\d{4}-\d\d-\d\d[T ]\d\d:\d\d:\d\d")
        result = self.succeeds("proofread", "list")
        self.assertNotIn("r-111111111111", result.stdout)
        self.assertIn("r-222222222222", result.stdout)

    def test_all_approval_accepts_add_delete_replace_and_keeps_history_immutable(self):
        self.write("main.tex", "Start \\kichoadd{r-111111111111}{added} "
                   "\\kichodelete{r-222222222222}{obsolete} end.\n")
        self.write("parts/body.tex", "\\kichoreplace{r-333333333333}{old}{new\n\nparagraph.}\n")
        self.succeeds("proofread", "approve", "r-111111111111", "--author", "Author")
        first_history = {str(p): p.read_bytes() for p in self.manifests()[0].parent.rglob("*") if p.is_file()}
        self.succeeds("proofread", "approve", "--all", "--author", "Author")
        self.assertEqual((self.root / "main.tex").read_text(), "Start {added} {} end.\n")
        self.assertEqual((self.root / "parts/body.tex").read_text(), "{new\n\nparagraph.}\n")
        self.assertEqual(len(self.manifests()), 2)
        self.assertEqual(first_history, {p: Path(p).read_bytes() for p in first_history})
        self.succeeds("proofread", "check")

    def test_bad_or_ambiguous_input_and_missing_author_never_partially_edit(self):
        cases = [r"\kichoadd{bad-id}{bad}", r"\kichoadd{r-222222222222}{unclosed",
                 r"\kichoadd{r-111111111111}{duplicate}",
                 r"\kichoadd{r-222222222222}{\kichodelete{r-333333333333}{nested}}"]
        self.write("main.tex", "\\kichoadd{r-111111111111}{valid}\n")
        for bad in cases:
            with self.subTest(bad=bad):
                self.write("z.tex", bad)
                before = self.snapshot()
                self.assertNotEqual(self.cli("proofread", "check").returncode, 0)
                self.assertNotEqual(self.cli("proofread", "approve", "r-111111111111", "--author", "Author").returncode, 0)
                self.assertEqual(before, self.snapshot())
        (self.root / "z.tex").unlink()
        for args in (("approve", "r-111111111111"),
                     ("approve", "r-111111111111", "--author", " "),
                     ("approve", "r-111111111111", "r-999999999999", "--author", "Author"),
                     ("approve", "--all", "r-111111111111", "--author", "Author")):
            before = self.snapshot()
            self.assertNotEqual(self.cli("proofread", *args).returncode, 0)
            self.assertEqual(before, self.snapshot())

    def test_approval_rejects_symlink_roots_sources_and_history_destinations(self):
        target = self.write("main.tex", "\\kichoadd{r-111111111111}{pending}\n")
        linked_root = Path(self.temp.name) / "linked-root"
        linked_root.symlink_to(self.root, target_is_directory=True)
        self.assertNotEqual(self.cli("proofread", "approve", "--all", "--author", "Author", "--root", str(linked_root)).returncode, 0)
        other = Path(self.temp.name) / "outside.tex"
        other.write_text("\\kichoadd{r-222222222222}{outside}\n")
        link = self.root / "linked.tex"
        link.symlink_to(other)
        before = target.read_bytes()
        result = self.cli("proofread", "approve", "--all", "--author", "Author")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_bytes(), before)
        self.assertIn("outside", other.read_text())
        link.unlink()
        outside_history = Path(self.temp.name) / "outside-history"
        outside_history.mkdir()
        (self.root / "archives").symlink_to(outside_history, target_is_directory=True)
        self.assertNotEqual(self.cli("proofread", "approve", "--all", "--author", "Author").returncode, 0)
        self.assertEqual(target.read_bytes(), before)
        self.assertEqual(list(outside_history.iterdir()), [])

    def test_handled_midway_write_failure_restores_sources_and_records_rollback(self):
        self.write("a.tex", "\\kichoadd{r-111111111111}{first accepted}\n")
        second = self.write("z.tex", "\\kichoadd{r-222222222222}{second accepted}\n")
        originals = self.snapshot()
        proofread = importlib.import_module("proofread")
        atomic_write = proofread.atomic_write
        failed = False

        def fail_second_write(path, data, mode):
            nonlocal failed
            if path.resolve() == second.resolve() and not failed:
                failed = True
                raise OSError("simulated second-source write failure")
            return atomic_write(path, data, mode)

        with patch.object(proofread, "atomic_write", side_effect=fail_second_write):
            with contextlib.redirect_stderr(io.StringIO()):
                result = proofread.main(["approve", "--all", "--author", "Author", "--root", str(self.root)])
        self.assertEqual(result, 1)
        self.assertTrue(failed)
        for name, data in originals.items():
            self.assertEqual((self.root / name).read_bytes(), data)
        manifest = self.manifests()[0]
        self.assertEqual(json.loads(manifest.read_text())["status"], "rolled-back")
        for name, data in originals.items():
            self.assertEqual((manifest.parent / "before" / name).read_bytes(), data)
        self.assertFalse((self.root / "archives/proofread/.approve-lock").exists())

    def test_approval_preserves_group_scope_and_control_word_boundaries(self):
        self.write("main.tex", r"""$\kichoadd{r-111111111111}{\alpha}bet$
\LaTeX\kichodelete{r-222222222222}{obsolete}book
$\kichoadd{r-333333333333}{\alpha} word$
\kichoreplace{r-444444444444}{old}{\bfseries bold} plain
""")
        self.succeeds("proofread", "approve", "--all", "--author", "Author")
        self.assertEqual((self.root / "main.tex").read_text(), r"""${\alpha}bet$
\LaTeX{}book
${\alpha} word$
{\bfseries bold} plain
""")

    def test_effective_custom_build_directory_is_excluded_with_option_precedence(self):
        for mode in ("config", "environment", "global"):
            with self.subTest(mode=mode):
                relative = "case-" + mode
                case_root = self.root / relative
                self.write(relative + "/main.tex", "\\kichoadd{r-111111111111}{Accepted body.}\n")
                configured = "./cache//pdf/" if mode == "config" else "./config-output/"
                self.write(relative + "/kicho.conf", "build_dir = " + configured + "\n")
                generated = self.write(relative + "/cache/pdf/generated.tex",
                                       b"\\kichoadd{r-111111111111}{Generated duplicate.}\r\n")
                generated_before = generated.read_bytes()
                env = dict(os.environ)
                env.pop("KICHO_BUILD_DIR", None)
                arguments = []
                authored = [(case_root / "main.tex", "r-111111111111")]
                if mode != "config":
                    authored.append((self.write(relative + "/config-output/body.tex",
                                                 "\\kichoadd{r-222222222222}{Configured path is now a source.}\n"),
                                     "r-222222222222"))
                    env["KICHO_BUILD_DIR"] = "./cache//pdf/"
                if mode == "global":
                    authored.append((self.write(relative + "/environment-output/body.tex",
                                                 "\\kichoadd{r-333333333333}{Environment path is now a source.}\n"),
                                     "r-333333333333"))
                    env["KICHO_BUILD_DIR"] = "./environment-output/"
                    arguments = ["--build-dir", "./cache//pdf/"]
                for action in ("check", "list"):
                    result = self.succeeds(*arguments, "proofread", action,
                                           "--root", str(case_root), env=env)
                    self.assertNotIn("generated.tex", result.stdout)
                    for _, identifier in authored:
                        self.assertIn(identifier, result.stdout)
                self.succeeds(*arguments, "proofread", "approve", "--all", "--author", "Author",
                              "--root", str(case_root), env=env)
                self.assertEqual(generated.read_bytes(), generated_before)
                for path, _ in authored:
                    self.assertNotIn("\\kichoadd", path.read_text())
                manifest_path = next((case_root / "archives/proofread").glob("*/manifest.json"))
                manifest = json.loads(manifest_path.read_text())
                self.assertNotIn("cache/pdf/generated.tex", {item["path"] for item in manifest["files"]})

    def test_submissions_refuse_pending_and_malformed_corrections(self):
        self.project()
        for body in (r"\kichoadd{r-222222222222}{pending}",
                     r"\kichoadd{r-222222222222}{unclosed"):
            self.write("parts/body.tex", body)
            before = self.snapshot()
            for args in (("submit", "--output", "standard"),
                         ("submit", "--arxiv", "--output", "arxiv")):
                with self.subTest(args=args, body=body):
                    self.assertNotEqual(self.cli(*args).returncode, 0)
                    self.assertFalse((self.root / args[-1]).exists())
                    self.assertEqual(before, self.snapshot())

    def test_submission_gate_checks_explicit_source_dependencies_under_build(self):
        self.project()
        self.write("main.tex", r"""\documentclass{article}
\usepackage{kichoproof}
\begin{document}
Approved text.\input{build/body.tex}
\end{document}
""")
        self.write("parts/body.tex", "Ordinary body.\n")
        self.write("build/body.tex", "\\kichoadd{r-333333333333}{Pending source in build.}\n")
        before = self.snapshot()
        for args in (("submit", "--output", "standard"),
                     ("submit", "--arxiv", "--output", "arxiv")):
            with self.subTest(args=args):
                result = self.cli(*args)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("r-333333333333", result.stdout + result.stderr)
                self.assertFalse((self.root / args[-1]).exists())
                self.assertEqual(before, self.snapshot())

    def test_submission_gate_also_checks_referenced_hidden_and_style_sources(self):
        self.project()
        self.write("main.tex", r"""\documentclass{article}
\usepackage{kichoproof,custom}
\begin{document}
Approved text.\input{.hidden.tex}
\end{document}
""")
        self.write("parts/body.tex", "Ordinary body.\n")
        for pending_source in (".hidden.tex", "custom.sty"):
            self.write(".hidden.tex", "Ordinary hidden input.\n")
            self.write("custom.sty", "\\ProvidesPackage{custom}\n")
            pending = r"\kichoadd{r-333333333333}{Pending correction.}"
            self.write(pending_source, pending if pending_source.endswith(".tex")
                       else "\\ProvidesPackage{custom}\n\\AtBeginDocument{" + pending + "}\n")
            before = self.snapshot()
            for args in (("submit", "--output", "standard"),
                         ("submit", "--arxiv", "--output", "arxiv")):
                with self.subTest(source=pending_source, args=args):
                    result = self.cli(*args)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("r-333333333333", result.stdout + result.stderr)
                    self.assertFalse((self.root / args[-1]).exists())
                    self.assertEqual(before, self.snapshot())

    def test_approved_submission_rebuilds_stale_pdf_and_keeps_accepted_content(self):
        self.project()
        self.succeeds("proofread", "approve", "--all", "--author", "Author")
        accepted = {name: (self.root / name).read_bytes() for name in ("main.tex", "parts/body.tex")}
        self.succeeds("submit", "--output", "standard", env=self.fake_builder())
        self.assertEqual((self.root / "standard/main.pdf").read_bytes(), b"FRESH-ACCEPTED-PDF")
        self.assertFalse((self.root / "standard/kichoproof.sty").exists())
        self.succeeds("submit", "--arxiv", "--output", "arxiv")
        with zipfile.ZipFile(self.root / "arxiv/arxiv-source.zip") as archive:
            self.assertNotIn("kichoproof.sty", archive.namelist())
            content = "\n".join(archive.read(name).decode() for name in archive.namelist() if name.endswith(".tex"))
            self.assertIn("new wording", content)
            self.assertIn("Added body.", content)
            self.assertNotIn("old wording", content)
            self.assertNotRegex(content, r"\\kicho(?:add|delete|replace)\{")
        for name, data in accepted.items():
            self.assertEqual((self.root / name).read_bytes(), data)
        self.assertEqual((self.root / "build/main.pdf").read_bytes(), b"STALE-RED-WORKING-PDF")


if __name__ == "__main__":
    unittest.main()
