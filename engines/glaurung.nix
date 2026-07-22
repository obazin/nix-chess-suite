{ lib, mkEngine, fetchFromGitHub }:

mkEngine rec {
  pname = "glaurung";
  version = "2.2";

  # Tord Romstad stopped developing Glaurung after 2.2 and the original
  # glaurungchess.com is gone; phenri/glaurung is a verbatim import of the
  # 2.2 distribution, including the upstream Copying.txt and Readme.txt.
  src = fetchFromGitHub {
    owner = "phenri";
    repo = "glaurung";
    rev = "1ac8827b1f0bf60de2c390d9e855980943ca4be5";
    hash = "sha256-pLsXNvyLxORnY/FEh/aeJBizkL6OGfOyQH2f9bcHSlA=";
  };

  sourceRoot = "source/src";

  # `all` also generates .depend; the binary target alone is enough.
  makeTarget = "glaurung";

  binaries = [ "glaurung" ];

  meta = with lib; {
    description = "Glaurung 2.2, Tord Romstad's UCI engine and the direct ancestor of Stockfish";
    homepage = "https://www.chessprogramming.org/Glaurung";
    # src/Makefile and every source file carry the GPLv3-or-later header
    # ("either version 3 of the License, or (at your option) any later
    # version"), and the distribution ships Copying.txt with GPLv3 text.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
