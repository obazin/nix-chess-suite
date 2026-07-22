{ lib, stdenv, mkEngine, fetchFromGitHub }:

mkEngine rec {
  pname = "tucano";
  version = "9.00";

  # Alcides Schulz's Tucano, pinned at v9.00 deliberately: it is the last
  # release before NNUE. From v10.00 the engine loads an external net
  # (tucano_nn03.bin) at runtime and plays far below strength without it, which
  # would need the net pinned and shipped. v9.00 is classical eval, self
  # contained, and sits squarely in this collection's 1800-2400 sparring band.
  src = fetchFromGitHub {
    owner = "alcides-schulz";
    repo = "Tucano";
    rev = "1d74edddc677f22452db7fc2efb055b2f1804d0b"; # tag 9.00
    hash = "sha256-WchMpWaaHVOlk3tyHshwfffh3BsC0piziN9R/iil1fs=";
  };

  # v9.00 ships no makefile at all -- only Windows .bat files and the VS
  # solution. The batch file documents the Linux build as a commented line:
  #   gcc -o tucano -O3 -flto -m64 -mtune=generic -s -lpthread -lm src/*.c
  # so there is nothing for mkEngine's stripArchFlags to act on; we invoke the
  # compiler here and simply omit the x86-only -m64/-mtune=generic. That build
  # line does not define EGTB_SYZYGY, so the Fathom tablebase prober in
  # src/fathom/ is excluded (it is `#ifdef EGTB_SYZYGY` throughout) -- Syzygy
  # support is optional and not needed for a sparring engine.
  #
  # bitboard.c selects _mm_popcnt_u64 only under MSVC; the GCC path uses
  # __builtin_popcountll, so aarch64 needs no popcount patching.
  buildPhase = ''
    runHook preBuild
    # globals.h already #defines NDEBUG itself, so we don't pass it here.
    $CC -o ${pname} -std=c99 -O3 -flto -Wfatal-errors \
      src/*.c -lpthread -lm
    runHook postBuild
  '';

  binaries = [ "tucano" ];

  meta = with lib; {
    description = "Tucano 9.00, Alcides Schulz's classical-eval UCI/XBoard engine (last pre-NNUE release)";
    homepage = "https://github.com/alcides-schulz/Tucano";
    # copying.txt is the GPLv3 text; every source header reads "either version
    # 3 of the License, or (at your option) any later version".
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
