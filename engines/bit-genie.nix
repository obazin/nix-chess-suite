{ lib, mkEngine, fetchFromGitHub }:

# Bit-Genie, Aryan Parekh's from-scratch C++17 NNUE engine (its own network,
# trained with guidance from the Koivisto authors — a distinct lineage, not a
# Stockfish fork). The trained net (src/defaultnet.nn, ~1.5 MB) is committed to
# the repo and embedded via INCBIN, so the finished binary is self-contained
# and nothing is fetched at build time. Despite being dormant since 2022 the
# code is portable: the only x86 intrinsic (nmmintrin.h / _mm_popcnt_u64 in
# BitBoardUtils-style headers) does not appear here — the network code uses no
# SIMD at all — so it builds cleanly on aarch64 with the scalar path.

mkEngine rec {
  pname = "bit-genie";
  version = "9";

  src = fetchFromGitHub {
    owner = "Aryan1508";
    repo = "Bit-Genie";
    rev = "v${version}";
    hash = "sha256-GmstbNQdc6mH4PIiyfNBF8dGYjQ91G4jNYuXkdnMWVM=";
  };

  sourceRoot = "source/src";

  # The makefile's default goal compiles every top-level *.cpp into "Bit-Genie".
  # EVALFILE defaults to defaultnet.nn (in this dir), which network.cpp bakes in
  # via INCBIN(Network, EVALFILE); no net needs pinning. -march=native is stripped
  # by mkEngine (stripArchFlags); the plain -flto is kept and clang honours it.
  binaries = [ "bit-genie" ];

  postPatch = ''
    # Build the binary lowercase (matching pname). Upstream's EXE is "Bit-Genie";
    # on a case-insensitive filesystem (macOS APFS) the default installPhase's
    # bin/Bit-Genie -> bin/bit-genie symlink resolves to the same path and errors,
    # so produce the pname-cased name directly and skip the symlink entirely.
    substituteInPlace makefile --replace-fail 'EXE := Bit-Genie' 'EXE := bit-genie'
  '';

  meta = with lib; {
    description = "Bit-Genie, Aryan Parekh's from-scratch C++17 NNUE UCI engine with an in-repo, embedded net";
    homepage = "https://github.com/Aryan1508/Bit-Genie";
    # LICENSE is the verbatim GPLv3 text; source files (e.g. src/main.cpp) carry
    # the "either version 3 ... or (at your option) any later version" notice.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
