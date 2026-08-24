unless (defined $ENV{'TEXMFVAR'} && length $ENV{'TEXMFVAR'}) {
  unless (-d 'build') {
    mkdir 'build' or die "Could not create build: $!";
  }
  unless (-d 'build/texmf-var') {
    mkdir 'build/texmf-var' or die "Could not create build/texmf-var: $!";
  }
  $ENV{'TEXMFVAR'} = 'build/texmf-var';
}

$pdf_mode = 4;
$lualatex = 'lualatex -synctex=1 -interaction=nonstopmode -file-line-error %O %S';
$bibtex = 'biber %O %B';
$out_dir = 'build';
$aux_dir = 'build';
$max_repeat = 5;
