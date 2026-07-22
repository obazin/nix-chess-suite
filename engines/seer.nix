{ lib, stdenv, mkEngine, fetchFromGitHub, fetchurl, llvmPackages }:

let
  # Seer's default net is weights/q0x35ddef41.bin, which is NOT in the repo;
  # the README compiles it in with
  #   wget .../releases/download/<id>/<id>.bin
  # then `make EVALFILE=...`. The net is embedded via INCBIN
  # (include/nnue/embedded_weights.h: `INCBIN(weights_file, EVALFILE)`), and
  # the engine defaults its Weights UCI option to "EMBEDDED", so once the file
  # is baked in the binary is fully self-contained. We pin exactly the id the
  # v2.8.0 build/makefile references (EVALFILE = weights/q0x35ddef41.bin).
  net = fetchurl {
    url = "https://github.com/connormcmonigle/seer-training/releases/download/0x35ddef41/q0x35ddef41.bin";
    hash = "sha256-8qY8QNWLx05jD8QL6ThftXidEp8wqiuYsCSg+PeOwYU=";
  };
in
mkEngine rec {
  pname = "seer";
  version = "2.8.0";

  src = fetchFromGitHub {
    owner = "connormcmonigle";
    repo = "seer-nnue";
    rev = "v${version}";
    hash = "sha256-zcqlrt584ckZwj3vVpyU6MVhO/8W9wYc9C9P7thiGEQ=";
  };

  # The Makefile lives in build/ and compiles the sources from there; INCBIN
  # resolves the net path (weights/q0x35ddef41.bin) relative to this dir.
  sourceRoot = "source/build";

  # The default goal (`flto`) piles on GCC-only LTO flags (-flto-partition=one,
  # -fwhole-program, -flto=jobserver) that clang rejects, and `pgo` runs the
  # engine mid-build. `binary` is the plain, non-PGO link target — the ARM- and
  # cross-friendly choice — so we build that directly.
  makeTarget = "binary";

  # -fopenmp is hardcoded in the base flags (Seer uses OpenMP SIMD in NNUE
  # inference); supply libomp so both the compile (omp.h) and the link (-lomp)
  # resolve.
  buildInputs = [ llvmPackages.openmp ];

  binaries = [ "seer" ];

  postPatch = ''
    # The Makefile compiles the sources in-place under ../src (and ../syzygy),
    # but nixpkgs only makes the sourceRoot (build/) writable — the sibling
    # directories are still read-only store copies, so the object files fail
    # with "Permission denied". Make the whole checkout writable.
    chmod -R u+w ..

    # Place the pinned net where INCBIN expects it (compiled from build/, so
    # the weights/ subdir must exist here). mkEngine's evalFile hook only
    # copies to a flat path, so we do it by hand to create the subdirectory.
    mkdir -p weights
    cp ${net} weights/q0x35ddef41.bin

    # Upstream uses GCC's -fconstexpr-ops-limit to raise the constexpr budget
    # for the compile-time-generated attack tables. clang spells the same knob
    # -fconstexpr-steps; without the rename clang errors on the unknown flag.
    # The makefile's constexpr budget flag is gcc's `-fconstexpr-ops-limit=`.
    # clang spells it `-fconstexpr-steps=`, so translate it ONLY when building
    # with clang (darwin); on gcc (linux) the original flag is correct and the
    # clang spelling would be rejected outright.
    ${lib.optionalString stdenv.cc.isClang ''
      substituteInPlace makefile \
        --replace-fail '-fconstexpr-ops-limit=' '-fconstexpr-steps='
    ''}

    # nnue/simd.h includes <x86intrin.h> unconditionally, which does not exist
    # on aarch64. The SIMD code paths are all guarded by `#if defined(__AVX2__)`
    # (absent on ARM, so the scalar fallbacks are used), so the include itself
    # just needs the same x86 guard.
    substituteInPlace ../include/nnue/simd.h \
      --replace-fail '#include <x86intrin.h>' '#if defined(__x86_64__) || defined(__i386__)
#include <x86intrin.h>
#endif'
  '';

  meta = with lib; {
    description = "Seer, Connor McMonigle's NNUE UCI engine using retrograde-learned WDL evaluation";
    homepage = "https://github.com/connormcmonigle/seer-nnue";
    # LICENSE.md is the GPLv3 text; src/seer.cc's header carries the
    # "either version 3 ... or (at your option) any later version" notice.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
