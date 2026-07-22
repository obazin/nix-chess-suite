{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub }:

# Willow, Adam Kulju's from-scratch C++20 engine — "the strongest mailbox
# engine in the world" (mailbox board representation, not bitboards), a lineage
# entirely its own. Its NNUE net (src/ida.nnue) is committed to the repo and
# embedded via INCBIN(nnue, "src/ida.nnue"), so the binary is self-contained.
# The SIMD layer (src/simd.h) has a real ARM NEON path guarded by __ARM_NEON__
# (which clang defines on aarch64), so it vectorises rather than falling back to
# scalar. Upstream compiles with -march=native, which mkEngine strips; without
# it clang targets the host baseline and NEON is still available (mandatory on
# aarch64), so the net still evaluates correctly.

mkEngine rec {
  pname = "willow";
  version = "4.0.0.1";

  src = fetchFromGitHub {
    owner = "Adam-Kulju";
    repo = "Willow";
    rev = version;
    hash = "sha256-Fvne3BP8G+QNS9uzpSVIZmjTINnTKjcn9KmQg01Lhf0=";
  };

  # Makefile's first (default) target compiles the src/willow.cpp unity build.
  # INCBIN resolves "src/ida.nnue" relative to the compile working directory,
  # which is the repo root (this sourceRoot), so the net is found in-tree.
  makeTarget = "willow";
  binaries = [ "willow" ];

  # Embedded-net engine: verify a real search returns a bestmove, so a net that
  # failed to embed (or a broken SIMD path) is caught, not just the handshake.
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
    description = "Willow, Adam Kulju's from-scratch C++20 mailbox NNUE UCI engine with an in-repo, embedded net";
    homepage = "https://github.com/Adam-Kulju/Willow";
    # LICENSE is the MIT licence, "Copyright (c) 2023 Adam Kulju".
    license = licenses.mit;
    maintainers = [ ];
  };
}
