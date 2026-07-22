{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub, fetchurl }:

# IMPORTANT PLATFORM CAVEAT
# Obsidian is x86_64-only. src/simd.h and src/bitboard.h include <immintrin.h>
# unconditionally and the NNUE inference has *only* AVX512/AVX2/SSSE3 code
# paths — there is no NEON or scalar fallback, on v16.0 or on master. It
# therefore cannot be built for aarch64 (neither aarch64-darwin nor
# aarch64-linux); attempting it fails with
#   immintrin.h: "This header is only meant to be used on x86 and x64".
# meta.platforms is restricted to x86_64 accordingly, which makes the flake
# skip it on this repo's macOS (aarch64-darwin) target. This file has NOT been
# build-verified — the only Nix host here is aarch64-darwin, where Obsidian is
# unbuildable by design. The net-pinning is verified (the fetchurl resolves);
# the x86 build wiring is best-effort and should be checked on an x86_64-linux
# runner before this engine is relied upon.

let
  # Obsidian embeds a single net via incbin (src/nnue.cpp: INCBIN(EmbeddedNNUE,
  # EvalFile)). The Makefile's DEFAULT_NET names the file and its `download-net`
  # target curls it from the Obsidian-nets release, which the sandbox forbids.
  # Pin the exact file and hand it to mkEngine as EVALFILE=; passing EVALFILE on
  # the make command line also trips the Makefile's `ifndef EVALFILE` guard, so
  # DOWNLOAD_NET is never set and download-net becomes a no-op.
  netFile = "net87perm.bin";
  net = fetchurl {
    name = netFile;
    url = "https://github.com/gab8192/Obsidian-nets/releases/download/nets/${netFile}";
    hash = "sha256-Jsw0zC+N8G0sDAzAwvrebNNUMmxcc+Nj+mKE0+M2KxY=";
  };
in
mkEngine rec {
  pname = "obsidian";
  version = "16.0";

  src = fetchFromGitHub {
    owner = "gab8192";
    repo = "Obsidian";
    rev = "v${version}";
    hash = "sha256-DZ8r+UjBz3l0+DSW+jpgUIkxujuVqlrMqmu4DJjVQwM=";
  };

  # Makefile sits at the repo root and compiles from there, so the incbin path
  # (EvalFile = net87perm.bin) resolves against the root. mkEngine copies the
  # pinned net to $sourceRoot/net87perm.bin.
  evalFile = net;
  evalFileName = netFile;

  # `make` runs a full PGO cycle. `nopgo` is the plain target. build=avx2 pins a
  # portable x86-64-v3 baseline; simd.h needs __AVX2__ (or higher) defined or it
  # has no vector type at all, so the arch flags MUST survive — do not let
  # mkEngine strip them.
  stripArchFlags = false;
  makeTarget = "nopgo";
  makeFlags = [ "build=avx2" ];
  binaries = [ "Obsidian" ];

  postPatch = ''
    # The Makefile hardcodes g++/gcc in its recipes; route them through the Nix
    # toolchain. The .c rule (fathom's tbprobe.c) is compiled as C++ with
    # -x c++, matching g++'s behaviour in the upstream PGO target — the pattern
    # rule otherwise feeds -std=c++17 to a C compilation, which is an error.
    substituteInPlace Makefile \
      --replace-fail 'g++ $(FLAGS) -c $< -o $@' '$(CXX) $(FLAGS) -c $< -o $@' \
      --replace-fail 'gcc $(FLAGS) -c $< -o $@' '$(CXX) $(FLAGS) -x c++ -c $< -o $@' \
      --replace-fail 'g++ $(FLAGS) $(OBJS) -o $(EXE)' '$(CXX) $(FLAGS) $(OBJS) -o $(EXE)'
    # -flto-partition=one is a GCC-only flag; clang does not understand it.
    substituteInPlace Makefile --replace-fail ' -flto-partition=one' ""
  '';

  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"
    out_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 12\n'; sleep 3; printf 'quit\n'; } \
      | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove' || {
      echo "FAIL: ${pname} produced no bestmove (NNUE net likely not loaded)" >&2
      echo "$out_txt" >&2; exit 1; }
    echo "ok: ${pname} speaks UCI and searches (net loaded)"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Obsidian, a strong NNUE-based UCI chess engine by Gabriele Lombardo (x86_64 only)";
    homepage = "https://github.com/gab8192/Obsidian";
    # LICENSE is the verbatim GPLv3 text. Source files carry no per-file
    # "or any later version" notice, so the conservative reading is
    # GPL-3.0-only. The net (Obsidian-nets) ships under the same project.
    license = licenses.gpl3Only;
    # x86_64-only: no ARM SIMD path upstream. See the header comment.
    platforms = [ "x86_64-linux" "x86_64-windows" ];
    maintainers = [ ];
  };
}
