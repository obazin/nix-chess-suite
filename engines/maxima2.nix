{ lib, mkEngine, fetchFromGitHub }:

# Maxima 2 (qm2), Erik van het Hof and Hermen Reitsma's engine — the completely
# rewritten successor to the Dutch QueenMaxima / BugChess NL lineage, now a
# 64-bit magic-bitboard UCI engine with a tapered classical evaluation (no
# NNUE, no external data files). Portable to aarch64: the sources use no x86
# intrinsics (popcount via the compiler builtin, KPK endgame knowledge shipped
# as a committed bitbase header src/eval_kpk_bb.h).
#
# Upstream builds with CMake, whose only arch flag is add_compile_options(
# -march=native) — invalid for Apple clang on aarch64. Rather than drive CMake,
# we compile the source set from src/CMakeLists.txt (the MAX2SRC library plus
# main.cpp and the w17 wild-variant tree) directly, like engines/minic.nix, with
# no -march so clang targets the host baseline.

mkEngine rec {
  pname = "maxima2";
  # Sources declare 2.0.0 (version.h.in: "2.0.0-<branch>-<rev>-<type>").
  version = "2.0.0-unstable-2018-03-19";

  src = fetchFromGitHub {
    owner = "hof";
    repo = "qm2";
    rev = "c764d15de975a5372f772d329bf1e316f9aa8460";
    hash = "sha256-YrNYCmYhhDJ/WN4cPsWoLP7wvleNY2tCcGWNf0LZ9dc=";
  };

  # We drive the compiler ourselves; nothing here is arch-flag-bearing to strip.
  stripArchFlags = false;

  postPatch = ''
    # engine.h / game.h include "version.h", which CMake generates from
    # version.h.in via configure_file. We bypass CMake, so materialise the
    # header by substituting the @CMake@ placeholders with fixed values.
    substituteInPlace src/version.h.in \
      --replace-fail '@GIT_BRANCH@' 'master' \
      --replace-fail '@REVISION@' 'c764d15' \
      --replace-fail '@CMAKE_BUILD_TYPE@' 'Release'
    cp src/version.h.in src/version.h

    # src/threadman.h uses POSIX spinlocks (pthread_spinlock_t, pthread_spin_*),
    # which Linux provides but Darwin's libpthread does not implement. Prepend a
    # self-guarded shim that, on Apple only, maps the spinlock API onto a plain
    # pthread_mutex (semantically fine here — it is just a short critical
    # section). On Linux the real spinlocks are used and the shim is inert.
    {
      printf '%s\n' \
        '#ifndef MAXIMA_SPIN_SHIM' \
        '#define MAXIMA_SPIN_SHIM' \
        '#if defined(__APPLE__)' \
        '#include <pthread.h>' \
        'typedef pthread_mutex_t pthread_spinlock_t;' \
        'static inline int pthread_spin_init(pthread_spinlock_t* l, int){ return pthread_mutex_init(l, 0); }' \
        'static inline int pthread_spin_destroy(pthread_spinlock_t* l){ return pthread_mutex_destroy(l); }' \
        'static inline int pthread_spin_lock(pthread_spinlock_t* l){ return pthread_mutex_lock(l); }' \
        'static inline int pthread_spin_unlock(pthread_spinlock_t* l){ return pthread_mutex_unlock(l); }' \
        '#endif' \
        '#endif'
      cat src/threadman.h
    } > src/threadman.h.new
    mv src/threadman.h.new src/threadman.h
  '';

  # Mirror src/CMakeLists.txt's MAX2SRC list (all src/*.cpp plus the w17 tree)
  # together with src/main.cpp. No -march; the code has no x86 intrinsics, so
  # clang's aarch64 baseline is sufficient.
  buildPhase = ''
    runHook preBuild
    $CXX -O3 -DNDEBUG -std=c++17 -Isrc \
      src/*.cpp src/w17/*.cpp \
      -o maxima2 -lpthread
    runHook postBuild
  '';

  binaries = [ "maxima2" ];

  meta = with lib; {
    description = "Maxima 2, Erik van het Hof and Hermen Reitsma's rewritten QueenMaxima-lineage magic-bitboard UCI engine";
    homepage = "https://github.com/hof/qm2";
    # Every source file (e.g. src/main.cpp, src/board.cpp) carries the header
    # "either version 3 of the License, or (at your option) any later version",
    # so the code is GPLv3-or-later. NOTE: the repo's LICENSE file is the older
    # GPLv2 text — a packaging mismatch — but the consistent per-file notices
    # govern, giving the more permissive (later-version) reading.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
