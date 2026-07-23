{ lib, mkEngine, fetchFromGitHub }:

mkEngine rec {
  pname = "gambitfruit";
  version = "4bx-20160428";

  # Ryan Benitez's original site is long gone. lazydroid/gambit-fruit is the
  # most complete surviving import: it carries the upstream readme.txt (with
  # Fruit's GPL notice), Benitez's readme_gambit.txt, and the opening book.
  # Upstream never tagged releases, so the rev is the pin.
  src = fetchFromGitHub {
    owner = "lazydroid";
    repo = "gambit-fruit";
    rev = "537715aa534ddb179330dec1660189a0e7769f71";
    hash = "sha256-j81RFFxDwHgkrOlo5HklKbqkMKc6+W0nznhyYWF7vNk=";
  };

  sourceRoot = "source/src";

  # `all` also generates .depend; the binary target alone is enough.
  makeTarget = "gfruit";

  binaries = [ "gfruit" ];

  postPatch = ''
    # `ld -s` is obsolete on Darwin and errors on recent cctools.
    substituteInPlace Makefile --replace-fail 'LDFLAGS += -s' '# LDFLAGS += -s'
  '';

  # OwnBook defaults to true with BookFile=performance.bin, which this
  # distribution does not ship; the only book present is book_small.bin, and
  # it lives at the repo root rather than next to the sources. Install it so
  # users can point BookFile at $out/share/gambitfruit/book_small.bin.
  dataFiles = [ "../book_small.bin" ];

  meta = with lib; {
    description = "Gambit Fruit, Ryan Benitez's aggressive Fruit 2.1 derivative with Toga II improvements";
    homepage = "https://www.chessprogramming.org/Gambit_Fruit";
    # readme.txt reproduces Fruit 2.1's own notice verbatim: "either version 2
    # of the License, or (at your option) any later version". As a derivative
    # of Fruit 2.1 it cannot be distributed under anything narrower. The repo
    # additionally ships a GPLv3 LICENSE file, which that grant permits.
    license = licenses.gpl2Plus;
    maintainers = [ ];
  };
}
