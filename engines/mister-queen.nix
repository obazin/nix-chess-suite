{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub }:

# MisterQueen — Michael Fogleman's independent magic-bitboard engine, a
# from-scratch didactic C codebase (not a fork of anything). Its opening book
# is embedded as a static array in src/book.c, so the binary is self-contained
# with no runtime data files. Untagged upstream; the head commit is pinned.
#
# Plain Makefile project. Two quirks handled below: the compiler variable is
# `C` (not the usual CC), and the produced binary is named `main`.

mkEngine rec {
  pname = "mister-queen";
  version = "0-unstable-2020-04-08";

  src = fetchFromGitHub {
    owner = "fogleman";
    repo = "MisterQueen";
    rev = "24c402a8cb31c1dfa432c54d60a3b541f1472096";
    hash = "sha256-vZLbDE2KkNQ7UcBXdUP4ypruT8mkNivfiqsSDgvi0Iw=";
  };

  # No -march anywhere in the Makefile, so nothing to strip; leave it off so
  # the elaborate Makefile is not touched by the sed pass.
  stripArchFlags = false;

  # The Makefile selects its compiler through `C ?= gcc`, not CC, so mkEngine's
  # CC=cc make flag does not reach it. Patch the default to the toolchain's cc
  # (gcc is absent under the Nix clang stdenv on Darwin).
  postPatch = ''
    substituteInPlace Makefile --replace-fail 'C ?= gcc' 'C ?= cc'
  '';

  # `make release` compiles into bin/release/main and symlinks ./main to it.
  makeTarget = "release";

  # The build artifact is called `main`; install it and let mkEngine symlink
  # bin/mister-queen -> main (bundled book means no dataFiles needed).
  binaries = [ "main" ];

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # MisterQueen searches on a background thread and is time-based: a bare `go`
  # defaults to a ~4s search and returns bestmove; `go depth` is also accepted.
  # It returns 0 from its command handler on quit, exiting cleanly. Require a
  # real bestmove, not just the handshake.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/mister-queen${stdenv.hostPlatform.extensions.executable}"

    out_txt=$( { printf 'uci\n';              sleep 0.5; \
                 printf 'isready\n';           sleep 0.5; \
                 printf 'position startpos\n'; sleep 0.5; \
                 printf 'go depth 10\n';       sleep 5; \
                 printf 'quit\n';              sleep 0.5; } \
               | timeout -s KILL 30 $emu "$bin" 2>/dev/null | tr -d '\r' || true)

    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: mister-queen did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove ' || {
      echo "FAIL: mister-queen returned no bestmove from 'go depth 10'" >&2
      echo "$out_txt" >&2; exit 1; }
    echo "ok: mister-queen speaks UCI and searches"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "MisterQueen, Michael Fogleman's independent magic-bitboard UCI engine in C with an embedded opening book";
    homepage = "https://github.com/fogleman/MisterQueen";
    # LICENSE.md in the repo root is verbatim MIT,
    # "Copyright (C) 2014 Michael Fogleman".
    # https://github.com/fogleman/MisterQueen/blob/master/LICENSE.md
    license = licenses.mit;
    maintainers = [ ];
  };
}
