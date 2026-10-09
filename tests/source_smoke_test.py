"""Real-tool checks for source safety and independently compilable exports."""
import json
from pathlib import Path
import re
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

    def compile(self, root=None, source='main.tex'):
        root = root or self.root
        (root / 'build').mkdir(exist_ok=True)
        result = self.run_command(['pdflatex', '-interaction=nonstopmode', '-halt-on-error',
                                   '-output-directory=build', source], root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def pages(self, result):
        match = re.search(r'Output written on .*?\((\d+) pages?,', result.stdout, re.S)
        self.assertIsNotNone(match, result.stdout)
        return int(match[1])

    def test_inline_input_beside_literal_block_survives_zip_export(self):
        self.write('parts/body.tex', 'Actual body before the literal block.\n')
        self.write('main.tex', r'''\documentclass{article}
\begin{document}
\input{parts/body}\begin{verbatim}
\input{missing-example}
\end{verbatim}
\end{document}
''')
        self.compile()
        self.assertFalse((self.root / 'build/main.fls').exists())
        result = self.cli('check', '--json')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.cli('submit', '--arxiv')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        unpacked = Path(self.temp.name) / 'inline-export'
        with zipfile.ZipFile(self.root / 'submission/arxiv-source.zip') as archive:
            self.assertIn('parts/body.tex', archive.namelist())
            self.assertIn(r'\input{missing-example}', archive.read('main.tex').decode())
            archive.extractall(unpacked)
        self.compile(unpacked)

    def test_clean_protects_pdf_that_overlaps_the_output_name_beside_literal_block(self):
        self.write('figure.tex', '\\documentclass{article}\n'
                   '\\begin{document}Original figure.\\end{document}\n')
        self.compile(source='figure.tex')
        original = (self.root / 'build/figure.pdf').read_bytes()
        self.write('artwork/main.pdf', original)
        self.write('kicho.conf', 'build_dir = artwork\n')
        self.write('main.tex', r'''\documentclass{article}
\usepackage{graphicx}
\begin{document}
\includegraphics[width=1cm]{artwork/main.pdf}\begin{verbatim}
Literal example.
\end{verbatim}
\end{document}
''')
        self.compile()
        self.assertFalse((self.root / 'build/main.fls').exists())
        result = self.cli('clean')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('source dependency', result.stderr)
        self.assertEqual((self.root / 'artwork/main.pdf').read_bytes(), original)

    def test_include_page_boundaries_survive_flatten_and_both_submissions(self):
        self.write('parts/one.tex', 'First included page.\n')
        self.write('parts/two.tex', 'Second included page.\n')
        self.write('main.tex', '\\documentclass{article}\n\\begin{document}\n'
                   '\\include{parts/one}\n\\include{parts/two}\n\\end{document}\n')
        (self.root / 'build/parts').mkdir()
        self.assertEqual(self.pages(self.compile()), 2)
        result = self.cli('flatten')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.pages(self.compile(source='dist/main.tex')), 2)
        result = self.cli('submit', '--output', 'standard')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.pages(self.compile(self.root / 'standard')), 2)
        result = self.cli('submit', '--arxiv')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        unpacked = Path(self.temp.name) / 'include-export'
        with zipfile.ZipFile(self.root / 'submission/arxiv-source.zip') as archive:
            archive.extractall(unpacked)
        self.assertEqual(self.pages(self.compile(unpacked)), 2)

    def test_main_collision_stops_submission_and_archive_still_compiles(self):
        self.write('kicho.conf', 'main = paper.tex\n')
        self.write('paper.tex', '\\documentclass{article}\n\\begin{document}\n'
                   '\\input{main}\n\\end{document}\n')
        self.write('main.tex', 'Original included body.\n')
        self.compile(source='paper.tex')
        for args in (('submit', '--output', 'standard'), ('submit', '--arxiv')):
            result = self.cli(*args)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('conflicts with generated output', result.stderr)
        self.assertFalse((self.root / 'standard').exists())
        self.assertFalse((self.root / 'submission').exists())
        self.assertFalse((self.root / 'arxiv-metadata.txt').exists())
        result = self.cli('archive')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        source = next((self.root / 'archives').glob('*/source'))
        self.compile(source, 'paper.tex')

    def test_split_preserves_compilable_literal_marker_examples(self):
        literal = (r'\begin% opening comment' + '\n{verbatim}\n% kicho:section example\n'
                   'Literal marker documentation.\n% kicho:end\n\\end{verbatim}\n')
        original = ('\\documentclass{article}\n\\begin{document}\n' + literal
                    + '% kicho:section actual\nActual section body.\n% kicho:end\n\\end{document}\n')
        self.write('main.tex', original)
        self.compile()
        result = self.cli('split')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(literal, (self.root / 'main.tex').read_text())
        self.assertFalse((self.root / 'sections/example.tex').exists())
        self.assertEqual((self.root / 'main.tex.kicho-backup').read_text(), original)
        self.compile()

    def test_one_line_abstract_matches_the_compilable_original(self):
        self.write('main.tex', '\\documentclass{article}\n\\title{Actual title}\n'
                   '\\author{Actual Author}\n\\begin{document}\n\\maketitle\n'
                   '\\begin{abstract}The actual short abstract.\\end{abstract}\n'
                   '\\section{Body}\nArticle body.\n\\end{document}\n')
        self.compile()
        result = self.cli('submit', '--arxiv')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        metadata = (self.root / 'arxiv-metadata.txt').read_text()
        abstract = metadata.split('Abstract:\n', 1)[1].split('\n\nComments:', 1)[0]
        self.assertEqual(abstract, 'The actual short abstract.')
        self.assertNotIn('Article body.', metadata)
        unpacked = Path(self.temp.name) / 'abstract-export'
        with zipfile.ZipFile(self.root / 'submission/arxiv-source.zip') as archive:
            archive.extractall(unpacked)
        self.compile(unpacked)

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
