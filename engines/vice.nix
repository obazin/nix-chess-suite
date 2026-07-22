{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub }:

# Vice — Bluefever Software's "Programming a Chess Engine in C" YouTube engine,
# the canonical teaching engine that speaks both UCI and xboard. The repository
# used to carry one directory per video; the current `main` branch has been
# pruned down to a single tree, Vice11/ — the final, complete engine — so
# pinning the head commit gives the canonical finished version rather than a
# mid-series snapshot. Untagged upstream, hence the commit pin.
#
# It is a plain C project: a handful of .c files plus a bundled tinycthread
# (a POSIX-pthread wrapper) for its lazy-SMP search. No arch-specific flags.

mkEngine rec {
  pname = "vice";
  version = "1.1-unstable-2026-06-26";

  src = fetchFromGitHub {
    owner = "bluefeversoft";
    repo = "vice";
    rev = "a89f82dcab34b74481d6504312e3d52bbba44320";
    hash = "sha256-Q/V9mvb59e3f+BRz1V2gZ0SNlqcF0s+hvUjx82OCvuw=";
  };

  sourceRoot = "source/Vice11/src";

  # The makefile hardcodes `gcc`, which does not exist under the Nix clang
  # stdenv on Darwin. Point it at the toolchain's cc (mkEngine also passes
  # CC=cc as a make flag, but this makefile ignores $(CC) and calls gcc
  # literally, so the name must be patched in the recipe).
  postPatch = ''
    substituteInPlace makefile --replace-fail 'gcc ' '$(CC) '
  '';

  # `make all` builds the single binary named vice12_smp; install it as `vice`
  # (mkEngine symlinks bin/vice -> the produced binary since it differs from
  # pname). The polyglot opening book (performance.bin) is opened relative to
  # the cwd and its absence is handled gracefully (UseBook stays off), so the
  # engine plays out of the box without shipping it.
  binaries = [ "vice12_smp" ];

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Vice's outer loop only enters the UCI handler after it reads a bare `uci`
  # line, so the handshake must lead with `uci`; it then handles isready /
  # position / go / quit and exits cleanly on quit. Require a real bestmove so
  # a broken search is caught, not just the handshake.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/vice${stdenv.hostPlatform.extensions.executable}"

    out_txt=$( { printf 'uci\n';              sleep 0.5; \
                 printf 'isready\n';           sleep 0.5; \
                 printf 'position startpos\n'; sleep 0.5; \
                 printf 'go depth 10\n';       sleep 5; \
                 printf 'quit\n';              sleep 0.5; } \
               | timeout -s KILL 30 $emu "$bin" 2>/dev/null | tr -d '\r' || true)

    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: vice did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove ' || {
      echo "FAIL: vice returned no bestmove from 'go depth 10'" >&2
      echo "$out_txt" >&2; exit 1; }
    echo "ok: vice speaks UCI and searches"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Vice, Bluefever Software's didactic UCI/xboard engine from the 'Programming a Chess Engine in C' series";
    homepage = "https://github.com/bluefeversoft/vice";
    # LICENSE in the repo root is verbatim MIT, "Copyright (c) 2022 bluefeversoft".
    # https://github.com/bluefeversoft/vice/blob/main/LICENSE
    license = licenses.mit;
    maintainers = [ ];
  };
}
