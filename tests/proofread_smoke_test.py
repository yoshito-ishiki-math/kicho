"""Real TeX checks for pending corrections, moving arguments, and diagnostics."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "lib/kicho/latex/kichoproof.sty"


class ProofreadSmoke(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="kicho-proofread-smoke-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copy2(PACKAGE, self.root / PACKAGE.name)

    def compile(self, body, *, japanese=False, passes=1):
        command = "lualatex" if japanese else "pdflatex"
        if not shutil.which(command):
            self.skipTest(f"{command} is unavailable")
        source = ((r"\documentclass{jlreq}" if japanese else r"\documentclass{article}")
                  + "\n\\usepackage{amsmath,kichoproof,hyperref}\n"
                  + "\\begin{document}\n" + body + "\n\\end{document}\n")
        (self.root / "main.tex").write_text(source, encoding="utf-8")
        # Keep font caches out of the checked-out source tree.
        environment = dict(os.environ, TEXMFVAR=str(self.root / "texmf-var"))
        for _ in range(passes):
            result = subprocess.run(
                [command, "-interaction=nonstopmode", "-halt-on-error", "main.tex"],
                cwd=self.root, env=environment, capture_output=True, text=True,
                timeout=120,
            )
            if result.returncode:
                break
        return result

    def test_text_math_paragraphs_and_moving_arguments(self):
        result = self.compile(r"""\tableofcontents
\section{A \kichoadd{r-000000000001}{revised} heading}
Ordinary black text. \kichoadd{r-000000000002}{Added text with {nested} groups
and inline math $x^2+1$.} Ordinary black text.

\kichodelete{r-000000000003}{Obsolete text with $x=0$.}
\kichoreplace{r-000000000004}{Old wording.}{New wording.}

\kichoadd{r-000000000005}{First added paragraph.

Second added paragraph.}
\kichoadd{r-000000000006}{\[\sum_{n=1}^{N}n=\frac{N(N+1)}2.\]}
Inline correction in math: $\kichoadd{r-000000000007}{x+1}=2$.
\begin{figure}
\caption{A \kichoreplace{r-000000000008}{former}{revised} caption}
\end{figure}
\begin{figure}
\caption{\kichoadd{r-000000000009}{A long caption whose correction is typeset
twice by LaTeX while measuring its width. This is one source correction,
even when the caption requires more than one line in the final document.}}
\end{figure}
\listoffigures
""", passes=2)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Token not allowed in a PDF string", result.stdout)
        self.assertTrue((self.root / "main.pdf").is_file())

    def test_japanese_text_and_display_math(self):
        result = self.compile(r"""\section{校正箇所の表示}
通常の本文。\kichoadd{r-111111111111}{追加した日本語と数式 $d(x,y)$。}
\kichodelete{r-222222222222}{削除する文章。}
\kichoreplace{r-333333333333}{修正前の説明。}{修正後の説明。}
\kichoadd{r-444444444444}{\[d(x,z)\leq d(x,y)+d(y,z).\]}
通常の本文に戻る。
""", japanese=True, passes=2)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_invalid_and_nested_ids_fail(self):
        for body, diagnostic in (
            (r"\kichoadd{invalid}{Text.}", "Invalid correction ID"),
            (r"\kichoadd{r-aaaaaaaaaaaa}{Outer \kichodelete{r-bbbbbbbbbbbb}{inner}}",
             "Nested corrections are unsupported"),
        ):
            with self.subTest(diagnostic=diagnostic):
                result = self.compile(body)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(diagnostic, result.stdout)


if __name__ == "__main__":
    unittest.main()
