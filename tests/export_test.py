"""Regression cases for diagnostics, portable exports, and failed snapshots."""
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
