{ lib, mkEngine, fetchFromGitHub }:

# Deepov, Romain Goussault's from-scratch C++14 UCI engine (magic-bitboard move
# generation, classical material/PST/mobility/pawn evaluation — an independent
# lineage, no NNUE and no external data). Portable to aarch64: the only x86
# intrinsic (nmmintrin.h / _mm_popcnt_u64) is guarded behind `#ifdef _MSC_VER`,
# so under clang the engine uses __builtin_popcountll, and the Makefile carries
# no -march flags at all.

mkEngine rec {
  pname = "deepov";
  # No tags or releases upstream; pin the latest commit on the default branch.
  version = "unstable-2021-04-25";

  src = fetchFromGitHub {
    owner = "RomainGoussault";
    repo = "Deepov";
    rev = "223e4d9ebf2202c0f2febd234c9507262f9cfbba";
    hash = "sha256-TaCQgz5Xtz3Ahn7GOSRWfF80lKtnlwxuD1eDuq9eZZA=";
  };

  # `all` also builds DeepovTesting (the unit-test binary, which pulls in the
  # test/ tree). Build only the engine, and lowercase the output name (see the
  # rule rename in postPatch) so the default installPhase does not try to create
  # a bin/Deepov -> bin/deepov symlink, which errors on a case-insensitive
  # filesystem (macOS APFS) where the two names are the same path.
  makeTarget = "deepov";
  binaries = [ "deepov" ];

  # Nothing arch-flag-bearing in the makefile to strip.
  stripArchFlags = false;

  postPatch = ''
    # The makefile bakes the standard and optimisation level into the CXX
    # variable itself (CXX = clang++ -std=c++14 -O3 -W). mkEngine overrides CXX
    # on the make command line to route through the Nix toolchain, which would
    # otherwise drop -std=c++14 -O3 and fail to compile the C++14 sources. Move
    # those flags into CC_FLAGS (used by the compile rule) so they survive the
    # CXX override.
    substituteInPlace makefile \
      --replace-fail 'CXX = clang++ -std=c++14 -O3 -W' 'CC_FLAGS += -std=c++14 -O3 -W'

    # Emit the engine binary lowercase (see makeTarget note above).
    substituteInPlace makefile --replace-fail 'Deepov: $(OBJ_FILES)' 'deepov: $(OBJ_FILES)'

    # msb()/lsb() use raw x86 bsrq/bsfq inline asm in the non-MSVC branch, which
    # the aarch64 assembler rejects. Swap in the portable compiler builtins:
    # bsrq (index of the highest set bit) == 63 - clz; bsfq (lowest) == ctz.
    substituteInPlace src/BitBoardUtils.hpp \
      --replace-fail '__asm__("bsrq %1, %0": "=r"(idx) : "rm"(bitboard));' 'idx = 63 - __builtin_clzll(bitboard);' \
      --replace-fail '__asm__("bsfq %1, %0": "=r"(idx): "rm"(bitboard) );' 'idx = __builtin_ctzll(bitboard);'
  '';

  meta = with lib; {
    description = "Deepov, Romain Goussault's from-scratch C++14 magic-bitboard UCI engine (classical evaluation)";
    homepage = "https://github.com/RomainGoussault/Deepov";
    # Every source file (e.g. src/Main.cpp, src/Board.cpp) carries the header
    # "either version 3 of the License, or (at your option) any later version",
    # so the code is GPLv3-or-later. NOTE: the repo's LICENSE file is the older
    # GPLv2 text — a packaging mismatch — but the consistent per-file notices
    # govern, giving the more permissive (later-version) reading.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
