{ lib, mkEngine, fetchFromGitHub, boost }:

# Napoleon, Marco Pampaloni's (crybot) from-scratch C++ engine. The account also
# hosts NapoleonZero (a Rust reimplementation) — this is the original C++ line.
#
# VERSION PIN: v1.5.0 is the last classical, hand-crafted-evaluation release.
# From v1.6 onward the engine was rewritten around an ONNX Runtime + CUDA neural
# evaluation (Makefile links -lonnxruntime -lcudart), which needs a GPU/ML stack
# and has no portable CPU fallback. v1.5.0 keeps Napoleon self-contained and in
# its ~2400 band, and must not be bumped past it for this collection.
#
# v1.5.0 ships no Makefile (only a qmake .pro), so we compile the sources
# directly, mirroring engines/cheng4.nix / engines/minic.nix.

mkEngine rec {
  pname = "napoleon";
  version = "1.5.0";

  src = fetchFromGitHub {
    owner = "crybot";
    repo = "Napoleon";
    rev = "v${version}";
    hash = "sha256-bCECEYvKdXltAF1pqObqxrn/ugdDFpdrYTGTdmgGQb4=";
  };

  # We drive the compiler ourselves; nothing here bears arch flags to strip.
  stripArchFlags = false;

  # benchmark.cpp and fenstring.cpp use header-only boost::algorithm::string; no
  # boost library is linked, only its headers are needed on the include path.
  buildInputs = [ boost ];

  postPatch = ''
    # utils.h's BitScanForward/Reset select an x86 `bsfq` inline-asm path on
    # `__GNUC__ && __LP64__`. clang defines both of those on aarch64, so it wrongly
    # takes the x86 branch and fails to assemble (`bsfq` is not an ARM mnemonic).
    # Narrow the guard to actual x86 so aarch64 falls through to the very next
    # branch, the portable __builtin_ctzll path.
    substituteInPlace utils.h \
      --replace-fail '#if defined(__GNUC__) && defined(__LP64__)' \
        '#if defined(__GNUC__) && defined(__LP64__) && (defined(__x86_64__) || defined(__i386__))'
  '';

  # -std=c++14: search.cpp uses the `register` storage-class keyword, which is a
  # hard error under C++17. The engine is otherwise host-baseline portable —
  # bit twiddling is via __builtin_ctzll/__builtin_popcountll (and, on x86, inline
  # asm), not vector intrinsics. Only the top-level *.cpp form the engine
  # (main.cpp holds the sole main()); the NapoleonPP/ subtree is an older
  # duplicate and is excluded.
  # Output to `napoleon`, not the upstream target name NapoleonPP: a NapoleonPP/
  # directory already exists in the tree, so linking to that name fails with
  # "path is a directory".
  buildPhase = ''
    runHook preBuild
    $CXX -O3 -DNDEBUG -std=c++14 -pthread \
      *.cpp -o napoleon -lpthread
    runHook postBuild
  '';

  binaries = [ "napoleon" ];

  meta = with lib; {
    description = "Napoleon, Marco Pampaloni's from-scratch C++ UCI engine (v1.5.0, classical hand-crafted evaluation)";
    homepage = "https://github.com/crybot/Napoleon";
    # LICENSE is the verbatim GPLv3 text.
    license = licenses.gpl3Only;
    maintainers = [ ];
  };
}
