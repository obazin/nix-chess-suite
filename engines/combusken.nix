# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally.
{ lib, stdenv, buildPackages, buildGoModule, fetchFromGitHub, mkEngine ? null }:

# Combusken, Marek Chrapek's classical (alpha-beta, hand-tuned eval) UCI engine
# in Go. Written by a DIFFERENT author and codebase from the other Go engines
# here (Counter, Blunder, Zurichess). Two things make it unlike them:
#
#  1. It bundles Jon Dart's Fathom Syzygy prober as a cgo package (fathom/,
#     .c + .h with `import "C"`). So unlike the pure-Go engines this needs a C
#     compiler and CGO_ENABLED=1 — both of which buildGoModule provides by
#     default on a native build.
#  2. Its one external dependency, golang.org/x/sys, is used ONLY by
#     transposition/new_transtable_linux.go (a `+build linux` file that mmaps
#     the TT). On this aarch64-darwin host the `+build !linux` sibling
#     new_transtable.go is compiled instead and x/sys is never imported, so the
#     require is dead weight. The repo also ships no go.sum, which would make a
#     normal module fetch fail on checksum verification. Dropping the unused
#     require in postPatch sidesteps both issues and lets vendorHash be null
#     (nothing left to fetch).
#
# Upstream is ARCHIVED (last commit 2022-01-16, past the v2.0.0 tag), so the
# final master commit is pinned rather than a moving branch.

buildGoModule rec {
  pname = "combusken";
  version = "2.0.0-unstable-2022-01-16";

  src = fetchFromGitHub {
    owner = "mhib";
    repo = "combusken";
    rev = "1eb34c7b2bac00c23302d22d0af70638df1b84f0";
    hash = "sha256-3vNTDAHu5xOYBnVBVKv6hJPtH+ptuyj1MING5we5h/s=";
  };

  # See header: the sole require (golang.org/x/sys) is Linux-only and unused on
  # this platform, and there is no go.sum to check it against. Delete it so the
  # module has no external dependencies and vendoring is a no-op.
  postPatch = ''
    sed -i -e '/golang.org\/x\/sys/d' go.mod

    # transposition/new_transtable_linux.go (build tag `linux`) is the only
    # thing that imports golang.org/x/sys — it uses hugepages via mmap. On
    # Linux it, not the dependency-free new_transtable.go (tag `!linux`), would
    # be compiled, reintroducing the x/sys import we just dropped. Force the
    # portable variant everywhere: delete the Linux file and lift the `!linux`
    # tag so new_transtable.go builds on all platforms. Only effect is that the
    # Linux build forgoes explicit hugepage allocation (transparent hugepages
    # still apply); play is identical.
    rm transposition/new_transtable_linux.go
    sed -i -e '\#// +build !linux#d' -e '\#//go:build !linux#d' \
      transposition/new_transtable.go

    # Bundled Fathom: tbprobe.c does `#include "tbchess.c"`, so tbchess.c is not
    # a standalone unit — its (all-static) helpers reference popcount/lsb/poplsb
    # that are only defined once tbprobe.c has included it. cgo nonetheless
    # compiles tbchess.c on its own, where those calls are implicit. Modern
    # clang makes an implicit declaration a hard error (older gcc only warned),
    # which is the sole thing that stops the C from building; the unused statics
    # are then optimised away at -O3, so the real definitions still come from
    # tbprobe.c and the link is clean. Downgrade just that diagnostic.
    substituteInPlace fathom/fathom.go \
      --replace-fail '-O3 -std=gnu11 -w' \
                     '-O3 -std=gnu11 -w -Wno-implicit-function-declaration'
  '';

  vendorHash = null;

  # combusken.go at the repo root is the only package to build; this skips the
  # tools/ helpers (bookgen etc.). cgo is left enabled so the bundled Fathom
  # prober (fathom/*.c) links in rather than falling back to fathom_stub.go.
  subPackages = [ "." ];

  ldflags = [ "-s" "-w" ];

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Same guarantee as the other engines: handshake to uciok, then require a
  # real bestmove from a search. Combusken parses a pipelined burst fine and
  # exits on quit, but the check is drip-fed and timeout-wrapped anyway for
  # uniformity with the finickier engines.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/combusken${stdenv.hostPlatform.extensions.executable}"

    out_txt=$( { printf 'uci\n';              sleep 0.5; \
                 printf 'isready\n';           sleep 0.5; \
                 printf 'position startpos\n'; sleep 0.5; \
                 printf 'go depth 10\n';       sleep 5; \
                 printf 'quit\n';              sleep 0.5; } \
               | timeout -s KILL 30 $emu "$bin" 2>/dev/null | tr -d '\r' || true)

    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: combusken did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove ' || {
      echo "FAIL: combusken returned no bestmove from 'go depth 10'" >&2
      echo "$out_txt" >&2; exit 1; }
    echo "ok: combusken speaks UCI and searches"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Combusken, Marek Chrapek's classical-evaluation UCI engine in Go with a bundled Fathom Syzygy prober";
    homepage = "https://github.com/mhib/combusken";
    # LICENSE in the repo root is the verbatim GPL-3.0 text and README states
    # "distributed under the GNU General Public License version 3 (GPL v3)"
    # with no "or later", so this is GPL-3.0-only. The bundled fathom/ prober
    # carries its own MIT notice (Copyright (c) 2015 basil00, mods by Jon Dart).
    # https://github.com/mhib/combusken/blob/master/LICENSE
    license = with licenses; [ gpl3Only mit ];
    mainProgram = "combusken";
    # Unix only: Combusken links Jon Dart's Fathom via cgo (CGO_ENABLED=1),
    # and cross-compiling Go+cgo to Windows needs a wired mingw C toolchain
    # that buildGoModule does not set up. Buildable on Windows only if the
    # cgo Fathom path is replaced; gated off until then.
    platforms = platforms.unix;
    maintainers = [ ];
  };
}
