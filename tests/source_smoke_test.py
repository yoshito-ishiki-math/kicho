"""Real-tool checks for source safety and independently compilable exports."""
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]


def png():
    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b'\x00\xff\xff\xff')) + chunk(b'IEND', b''))


class SourceSmoke(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='kicho-source-smoke-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / '日本語 Paper'
        self.root.mkdir()
        (self.root / '.latexmkrc').write_text('$pdf_mode = 1;\n')
        for name in ('bib', 'figures', 'build'):
            (self.root / name).mkdir()

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data if isinstance(data, bytes) else data.encode())
        return path

    def run_command(self, args, root=None):
        return subprocess.run(args, cwd=root or self.root, capture_output=True,
                              text=True, timeout=45)

    def cli(self, *args):
        return self.run_command(['/bin/bash', str(ROOT / 'bin/kicho'), *args])

    def compile(self, root=None):
        root = root or self.root
        (root / 'build').mkdir(exist_ok=True)
        result = self.run_command(['pdflatex', '-interaction=nonstopmode', '-halt-on-error',
                                   '-output-directory=build', 'main.tex'], root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_multiline_grouped_zip_compiles_without_recorder(self):
        self.write('outer/one.png', png())
        self.write('inner/two.png', png())
        self.write('main.tex', r'''\documentclass{article}
\usepackage{graphicx}
\graphicspath{{outer/}}
\begin{document}
{\graphicspath{{inner/}}\includegraphics[width=2mm]{two}}
\includegraphics
[width=2mm]
{one}
\begin{minipage}{20mm}
\graphicspath{{inner/}}\includegraphics[width=2mm]{two}
\end{minipage}
\includegraphics[width=2mm]{one}
\end{document}
''')
        self.compile()
        self.assertFalse((self.root / 'build/main.fls').exists())
        result = self.cli('check', '--json')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)['errors'], 0)
        result = self.cli('submit', '--arxiv')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        unpacked = Path(self.temp.name) / 'unpacked'
        with zipfile.ZipFile(self.root / 'submission/arxiv-source.zip') as archive:
            self.assertIn('outer/one.png', archive.namelist())
            self.assertIn('inner/two.png', archive.namelist())
            archive.extractall(unpacked)
        self.compile(unpacked)

    def test_clean_protects_original_figure(self):
        self.write('figures/original.png', png())
        self.write('kicho.conf', 'build_dir = figures\n')
        self.write('main.tex', r'''\documentclass{article}
\usepackage{graphicx}
\begin{document}\includegraphics{figures/original.png}\end{document}
''')
        self.compile()
        result = self.cli('clean')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual((self.root / 'figures/original.png').read_bytes(), png())

    def test_real_cleanup_preserves_notes(self):
        self.write('main.tex', '\\documentclass{article}\n\\begin{document}Body.\\end{document}\n')
        result = self.cli('build')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.root / 'build/main.pdf').exists())
        self.write('build/notes.md', 'ORIGINAL NOTES\n')
        result = self.cli('clean')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.root / 'build/main.pdf').exists())
        self.assertEqual((self.root / 'build/notes.md').read_text(), 'ORIGINAL NOTES\n')

    def test_compilable_directory_link_is_rejected_before_export(self):
        self.write('data/body.tex', 'Original body.\n')
        (self.root / 'alias').symlink_to('data', target_is_directory=True)
        self.write('main.tex', '\\documentclass{article}\n'
                   '\\begin{document}Before \\input{alias/body} after.\\end{document}\n')
        self.compile()
        result = self.cli('check', '--json')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        result = self.cli('submit', '--arxiv')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'submission').exists())
        self.assertEqual((self.root / 'data/body.tex').read_text(), 'Original body.\n')


if __name__ == '__main__':
    unittest.main()
