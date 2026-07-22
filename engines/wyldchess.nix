{ lib, mkEngine, fetchFromGitHub }:

# WyldChess, Manik Charan's from-scratch C11 engine. Plain hand-crafted
# evaluation, no NNUE and no net — fully self-contained. The single binary
# speaks both XBoard and UCI, switching on the first protocol line it reads
# (main.c dispatches "uci" -> uci_loop), so feeding it `uci` gives a UCI engine.

mkEngine rec {
  pname = "wyldchess";
  version = "1.51";

  src = fetchFromGitHub {
    owner = "Mk-Chan";
    repo = "WyldChess";
    rev = "b61f496cafcd697c1aa402b852b31ae9d3b902e6";
    hash = "sha256-uvco7mOniNjYwInjxGZGiR91TnqgUR898cKtJTbs5oA=";
  };

  sourceRoot = "source/src";

  # Default `all` target adds no arch flags (the popcnt/bmi targets do, but we do
  # not use them). WyldChess's own popcount is __builtin_popcountll, and the
  # bundled Syzygy prober guards its x86 <popcntintrin.h>/<nmmintrin.h> includes
  # behind `__x86_64__ && __SSE4_2__`, falling back to a software popcount
  # otherwise — so the aarch64 build pulls in no x86 headers. mkEngine forces
  # CC=cc, which is the correct C compiler for these C11 sources, so no compiler
  # patching is needed. The bare -flto survives the arch-flag strip.
  binaries = [ "wyldchess" ];

  meta = with lib; {
    description = "WyldChess, Manik Charan's from-scratch C11 UCI/XBoard engine with Syzygy support";
    homepage = "https://github.com/Mk-Chan/WyldChess";
    # LICENSE is the verbatim GPLv3 text; every source header carries the
    # "version 3 ... or (at your option) any later version" notice.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
