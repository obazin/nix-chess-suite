{ lib, mkEngine, fetchFromGitHub }:

# Loki, Niels Abildskov's from-scratch C++17 engine. This pins the post-v3.5.0
# HEAD of the Loki3 line, which is a pure hand-crafted evaluation (evaluation.cpp
# + psqt.cpp) with NO NNUE and no net to fetch, so the build is fully
# self-contained. (Later experimental Loki work adds NNUE; this classical branch
# is deliberately the simpler, net-free choice.)

mkEngine rec {
  pname = "loki";
  version = "3.5.0";

  src = fetchFromGitHub {
    owner = "BimmerBass";
    repo = "Loki";
    rev = "4787174d9d66ee052aef6d7cd15dec22c8aad664";
    hash = "sha256-4Di/cCFPs3WRj/ulJWMmQJYde3BQngBDXt+0rtEawbA=";
  };

  # The makefile sits at the repo root and compiles Loki/*.cpp from there, so the
  # source tree is unpacked in place — no sourceRoot override needed. The default
  # `all` target is the only one.

  # mkEngine strips -march=native and -m64 from CXXFLAGS. USE_POPCNT stays on,
  # which on GCC/clang selects countBits' __builtin_popcountll path (the
  # _mm_popcnt_u64 branch is guarded to MSVC/ICC-on-Windows only).
  binaries = [ "Loki3" ];

  postPatch = ''
    # evaltable.h uses size_t (EVAL_TABLE_SIZE) but includes only <cstdint>.
    # libstdc++ drags <cstddef> in transitively so upstream's g++ build compiles;
    # clang's libc++ does not, so size_t is undeclared. Add the correct include.
    substituteInPlace Loki/evaltable.h \
      --replace-fail '#include <cstdint>' '#include <cstdint>
#include <cstddef>'

    # bitboard.h includes <nmmintrin.h> (x86 SSE4.2) unconditionally for
    # countBits, but on GCC/clang countBits actually uses __builtin_popcountll —
    # the header is never needed there and does not exist on aarch64. Guard the
    # include to x86 so the ARM build sees only the builtin path.
    substituteInPlace Loki/bitboard.h \
      --replace-fail '#include <nmmintrin.h> // Used for countBits' \
        '#if defined(__x86_64__) || defined(__i386__)
#include <nmmintrin.h> // Used for countBits
#endif'

    # The `all` recipe hardcodes g++; route it through the Nix toolchain so the
    # clang c++ driver (and any cross toolchain) is honoured.
    substituteInPlace makefile \
      --replace-fail 'g++ ''${SOURCES}' '$(CXX) ''${SOURCES}'
  '';

  meta = with lib; {
    description = "Loki, Niels Abildskov's from-scratch C++17 UCI engine (classical hand-crafted evaluation, net-free)";
    homepage = "https://github.com/BimmerBass/Loki";
    # LICENSE is the verbatim GPLv3 text; every source header carries the
    # "version 3 ... or (at your option) any later version" notice.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
