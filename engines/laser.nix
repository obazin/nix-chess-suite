{ lib, mkEngine, fetchFromGitHub }:

# Laser, Jeffrey (and Michael) An's C++11 hand-crafted-evaluation engine. A
# clean, strong (~3280) but unmaintained classical engine — no NNUE, no net, no
# data files, so the source build is fully self-contained. This is the last
# commit on master (reporting itself as "1.8 beta").

mkEngine rec {
  pname = "laser";
  version = "1.8-beta";

  src = fetchFromGitHub {
    owner = "jeffreyan11";
    repo = "uci-chess-engine";
    rev = "6e60f3af0e6e2fdfb4a327c5edd3267868e34e63";
    hash = "sha256-lnGW52C90ghhEL0g0sM/3kJa9MbzXXm69PrO7TOiHJA=";
  };

  sourceRoot = "source/src";

  # Default target is `all` -> uci. mkEngine strips the -msse3/-mpopcnt and the
  # optional -march=haswell; count() uses __builtin_popcountll unconditionally,
  # and the bundled Syzygy prober has no x86-only code path, so the aarch64 build
  # is portable. The bare -flto survives the strip and clang honours it.
  binaries = [ "laser" ];

  postPatch = ''
    # The Makefile drives its C++ build through $(CC) (assigned g++). mkEngine
    # forces CC to the C compiler `cc` on the make command line, which would then
    # compile these C++ sources with a C driver and fail. Rewrite the recipe uses
    # of $(CC) to $(CXX) (mkEngine passes CXX=c++); the `CC = g++` assignment
    # itself holds no $(CC) reference, so this touches only the compile/link
    # commands.
    substituteInPlace Makefile --replace-fail '$(CC)' '$(CXX)'
  '';

  meta = with lib; {
    description = "Laser, Jeffrey An's C++ hand-crafted-evaluation UCI engine with Syzygy support";
    homepage = "https://github.com/jeffreyan11/uci-chess-engine";
    # COPYING is the verbatim GPLv3 text; every source header carries the
    # "version 3 ... or (at your option) any later version" notice.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
