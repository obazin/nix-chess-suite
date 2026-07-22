{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub }:

# Marvin, Martin Danielsson's from-scratch C NNUE engine. The cleanest of this
# batch: a plain Makefile with an explicit `arch=aarch64` target (NEON NNUE
# inference, portable popcount) alongside the x86 tiers, and the trained net
# committed in-repo at res/eval.nnue and embedded via INCBIN. Nothing is
# fetched at build time, so the binary is self-contained.

mkEngine rec {
  pname = "marvin";
  version = "6.3.0";

  src = fetchFromGitHub {
    owner = "bmdanielsson";
    repo = "marvin-chess";
    rev = "v${version}";
    hash = "sha256-t1mWMPuIDJQ7kpw+xYTB0WAS79sS4ssr369+cu7eSKI=";
  };

  # Pick the arch tier explicitly. `aarch64` is a first-class Makefile target:
  # it defines USE_NEON (src/simd.c gates <immintrin.h> behind USE_AVX2 and uses
  # <arm_neon.h> under USE_NEON) and USE_POPCNT, and emits *no* x86 codegen
  # flags — so there is nothing for mkEngine to strip and its arch-flag scrub
  # stays off. On x86_64 fall back to the portable modern tier (SSE/POPCNT, not
  # AVX2-only). INCBIN bakes res/eval.nnue in, so no EVALFILE handling is needed.
  stripArchFlags = false;
  makeTarget = "marvin";
  makeFlags = [ (if stdenv.hostPlatform.isAarch64 then "arch=aarch64" else "arch=x86-64-modern") ];
  binaries = [ "marvin" ];

  postPatch = ''
    # Upstream builds -Werror; a newer clang than the author tested turns fresh
    # diagnostics (e.g. in the vendored Fathom prober) into hard failures. Drop
    # it so a compiler-version bump does not break the build.
    substituteInPlace Makefile --replace-fail ' -Werror' ""
  '';

  # Embedded-net engine: verify it actually searches, not just that it answers
  # the UCI handshake, so a net that failed to bake in is caught.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"
    out_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 10\n'; sleep 4; printf 'quit\n'; } \
      | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove' || {
      echo "FAIL: ${pname} produced no bestmove (NNUE net likely not embedded)" >&2
      echo "$out_txt" >&2; exit 1; }
    echo "ok: ${pname} speaks UCI and searches (net embedded)"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Marvin, Martin Danielsson's from-scratch NNUE UCI chess engine with a committed, embedded net";
    homepage = "https://github.com/bmdanielsson/marvin-chess";
    # LICENSE is the verbatim GPLv3 text; every source file (e.g. src/main.c)
    # carries the "either version 3 ... or (at your option) any later version"
    # notice, so GPL-3.0-or-later.
    license = licenses.gpl3Plus;
    mainProgram = "marvin";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
