{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub, fetchurl }:

# On aarch64 Winter's SIMD layer wants sse2neon.h (its `_ARM` code path does
# `#include "sse2neon.h"`), but that header is NOT committed in the repo — only
# the x86 SSE/AVX headers are, and upstream's aarch64 Makefile target is an
# Android build that vendors it out-of-tree. Pin the upstream single-header
# sse2neon (MIT) so the ARM path has a real SSE->NEON shim; x86_64 keeps the
# native SSE path and never sees this file.
let
  sse2neon = fetchurl {
    url = "https://raw.githubusercontent.com/DLTcollab/sse2neon/v1.7.0/sse2neon.h";
    hash = "sha256-w24TVcGiLZwzV8lF0e+L0AXLHw97N45ld6ReqWkxoIM=";
  };
in

# Winter, Jonathan Rosenthal's engine. A distinct lineage: its evaluation is a
# hand-rolled logistic-regression / small dense network (NOT a Stockfish-style
# NNUE), STL-only, with the trained float weights committed in-repo at
# rn16HD64b.bin and baked into the binary via INCBIN
# (src/net_evaluation.cc: INCBIN(float_t, NetWeights, "rn16HD64b.bin")).
# Nothing is fetched at build time, so the binary is self-contained.

mkEngine rec {
  pname = "winter";
  # settings.h reports engine_version = "5.0"; the pinned commit is a few
  # commits past the v5.0 tag but still reports 5.0.
  version = "5.0";

  src = fetchFromGitHub {
    owner = "rosenthj";
    repo = "Winter";
    # No tag at the pinned tree; take the reproducible commit directly.
    rev = "456b1393a939ae497990052fdda757b24d6bb38d";
    hash = "sha256-iAzWPLXmyQIWBywDkjOH2Oq5RFqOKUDQOCO4tKGJ/HM=";
  };

  # The default (non-Android) Makefile branch hardcodes clang++ with
  # `-march=native -m64 -flto`. Those x86 codegen flags are what mkEngine's
  # arch-flag scrub removes (leaving a portable aarch64 build); the two ARM
  # branches target the Android NDK cross-compilers we do not have, so we let
  # the scrub handle the default branch instead of selecting ARCH=aarch64.
  # The in-Makefile `CXX=clang++` assignment is overridden by mkEngine passing
  # CXX= on the make command line (command-line assignments win in make).
  binaries = [ "Winter" ];

  # On aarch64 the default Makefile branch (the one we use) compiles the x86
  # SSE path unless `_ARM` is defined; with `_ARM` the SIMD layer switches to
  # `#include "sse2neon.h"`. Drop the pinned header into src/ and define _ARM so
  # the NEON shim is used. mkEngine's arch-flag scrub runs before this hook and
  # has already removed -m64/-march=native, so we only add the define; injecting
  # into every branch's -Wno-sign-compare is harmless since make only evaluates
  # the active branch. x86_64 is left on its native SSE/AVX path untouched.
  postPatch = lib.optionalString stdenv.hostPlatform.isAarch64 ''
    cp ${sse2neon} src/sse2neon.h
    substituteInPlace Makefile \
      --replace-fail '-Wno-sign-compare' '-Wno-sign-compare -D_ARM'
  '';

  # Install the binary directly as lowercase `winter`. mkEngine's default
  # installPhase would place it as bin/Winter and then symlink bin/winter ->
  # bin/Winter (because the build name differs from pname); on a
  # case-insensitive filesystem (the default on macOS) those two names are the
  # same path and `ln` errors, so install straight to the pname instead.
  installPhase = ''
    runHook preInstall
    install -Dm755 Winter "$out/bin/winter${stdenv.hostPlatform.extensions.executable}"
    runHook postInstall
  '';

  # Weights are embedded (like an NNUE net), so verify the engine actually
  # searches and returns a bestmove, not just that it answers the handshake —
  # a failure to bake in rn16HD64b.bin would otherwise slip through.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"
    out_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 10\n'; sleep 4; printf 'quit\n'; } \
      | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove' || {
      echo "FAIL: ${pname} produced no bestmove (embedded weights likely not baked in)" >&2
      echo "$out_txt" >&2; exit 1; }
    echo "ok: ${pname} speaks UCI and searches (weights embedded)"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Winter, Jonathan Rosenthal's engine with a distinct logistic-regression evaluation and committed, embedded weights";
    homepage = "https://github.com/rosenthj/Winter";
    # Copying.txt is the verbatim GPLv3 text; src/main.cc carries the
    # "either version 3 ... or (at your option) any later version" notice.
    license = licenses.gpl3Plus;
    mainProgram = "Winter";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
