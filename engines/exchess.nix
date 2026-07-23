{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub }:

# EXchess (now developed as Leaf), Daniel C. Homan's engine — an independent
# lineage in on-and-off development from 1997 through the 2017 v7.97b release
# (~2772 CCRL), with a classical hand-crafted evaluation, PVS, null-move, LMR,
# SEE and lazy SMP.
#
# IMPORTANT PROVENANCE NOTE. The brief called for pinning a "pre-2026 tag" for a
# classic UCI build, but the actual repository does not support that:
#   * dan-homan/Leaf has NO tags at all, and its entire git history begins on
#     2026-03-01 with a single "Initial commit of EXchess source" — there is no
#     pre-2026 commit to pin.
#   * That pristine classic source speaks ONLY xboard/CECP and an interactive
#     CLI; it has NO UCI support. UCI was added later, in the 2026 restart
#     (commit 70721ad, "uci: add full UCI protocol support"), which also
#     introduced an optional Stockfish-style NNUE.
# So a "classic EXchess that speaks UCI" cannot come from a pre-2026 state. What
# IS faithful to the classic engine is its hand-crafted evaluation, which the
# 2026 tree still uses whenever NNUE is left off (define.h defaults NNUE to 0).
# We therefore pin the first UCI-capable commit and build with NNUE disabled:
# the genuine classic EXchess brain, self-contained (no net, no data files),
# exposed over the added UCI layer. License is GPL-3.0 either way.

mkEngine rec {
  pname = "exchess";
  version = "7.97b";

  src = fetchFromGitHub {
    owner = "dan-homan";
    repo = "Leaf";
    # First commit to add UCI (2026-03-19). NNUE defaults off, so this builds
    # the classic hand-crafted evaluation; pinned explicitly as there are no
    # upstream tags.
    rev = "70721add063db1db6d3b18de8aef0b99f55a4794";
    hash = "sha256-iHfy4pERyLNiGsgiFTfvyHdk8DVkZJFG/i5esDldxRI=";
  };

  # We drive the compiler ourselves; nothing here is arch-flag-bearing to strip.
  stripArchFlags = false;

  # Mirror src/comp.pl's compile of the src/Leaf.cc unity file (it #includes
  # every .cpp), but:
  #   * NNUE is left at its define.h default of 0 — the classic eval. The NNUE
  #     path (src/nnue.cpp) is then inert; its <arm_neon.h>/<immintrin.h>
  #     includes are arch-guarded and compile cleanly but unused on aarch64.
  #   * comp.pl forces -march=native -mtune=native on Darwin, which Apple clang
  #     rejects on aarch64; we pass no -march so clang targets the host baseline.
  #   * TABLEBASES stays at its default of 0 (Nalimov tb/tbindex.c is not
  #     redistributed in the tree), and the FLTK GUI is behind `#if FLTK_GUI`,
  #     which we never define.
  # Leaf.cc's "../src/foo.cpp" includes resolve back into src/ when the unity
  # file itself is compiled at src/Leaf.cc.
  buildPhase = ''
    runHook preBuild
    $CXX -O3 -DNDEBUG -std=gnu++17 -funroll-loops -ffast-math -flto \
      -D VERS='"${version}"' -Wno-unused-result -Wno-narrowing \
      src/Leaf.cc -o exchess -pthread
    runHook postBuild
  '';

  binaries = [ "exchess" ];

  # Protocol is auto-detected; confirm UCI mode answers and a real search
  # returns a bestmove. (A missing search.par prints a harmless
  # "NoParFile--Using defaults" and compiled defaults are used.)
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"
    out_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 10\n'; sleep 4; printf 'quit\n'; } \
      | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove' || {
      echo "FAIL: ${pname} produced no bestmove" >&2; echo "$out_txt" >&2; exit 1; }
    echo "ok: ${pname} speaks UCI and searches (classic eval)"
    runHook postInstallCheck
  '';

  meta = with lib; {
    # Gated off Windows: POSIX-only (sockets/FD_SET, sysconf, sys/resource.h).
    platforms = platforms.unix;
    description = "EXchess/Leaf (classic hand-crafted evaluation, NNUE disabled), Daniel C. Homan's independent-lineage UCI engine";
    homepage = "https://github.com/dan-homan/Leaf";
    # src/license.txt is the verbatim GPLv3 text; source headers (e.g.
    # src/main.cpp) say only "Released under the GNU public license" with no
    # per-file "or any later version" notice, so the conservative reading is
    # GPL-3.0-only.
    license = licenses.gpl3Only;
    maintainers = [ ];
  };
}
