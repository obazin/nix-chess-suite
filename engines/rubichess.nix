# RubiChess is a C++ Makefile project, but the way it consumes its NNUE net does
# not fit mkEngine, so this is a standalone derivation. The meta fields and the
# UCI smoke test below mirror lib/mkEngine.nix.
#
# Net handling. RubiChess does NOT commit or ship its net; the Makefile downloads
# it from github.com/Matthies/NN at build time (name taken from NNUEDEFAULT in
# RubiChess.h) and embeds it into the binary with `ld -r -b binary net.nnue`.
# That embed path is a hard blocker here for two reasons: the download is
# sandbox-forbidden, and `ld -r -b binary` is a GNU-ld feature the macOS linker
# (cctools ld) does not implement, so the embedded build cannot be produced on
# darwin at all.
#
# Instead we build WITHOUT embedding (no EVALFILE) and pin the net as a data
# file installed next to the binary. RubiChess, when not built with an embedded
# net, searches for its default net (NNUEDEFAULTSTR) in the working directory
# and then in the executable's own directory - main.cpp derives that directory
# from argv[0] - so a net beside the binary is found and loaded at startup.
#
# `mkEngine` is accepted and ignored so callPackage can pass it uniformly.
{ lib, stdenv, buildPackages, fetchFromGitHub, fetchurl, zlib, mkEngine ? null }:

let
  # The net named by NNUEDEFAULT in RubiChess.h at this release
  # (nn-bc638d5ec9-20240730.nnue). Must match the engine's expected net exactly;
  # bump it in lockstep with the engine rev.
  netName = "nn-bc638d5ec9-20240730.nnue";
  net = fetchurl {
    url = "https://github.com/Matthies/NN/raw/main/${netName}";
    hash = "sha256-vGONXsnxXl3npNHDL3II5OfPiJ5WbSJTCZFa44plQrU=";
  };
in
stdenv.mkDerivation rec {
  pname = "rubichess";
  version = "20240817";

  src = fetchFromGitHub {
    owner = "Matthies";
    repo = "RubiChess";
    rev = version;
    hash = "sha256-eUPHqcme8g7BmmwxCyvOw5/1gbTWCPCYYJC6IpdMzhI=";
  };

  sourceRoot = "source/src";

  # RubiChess bundles a modified zlib (used to transparently decompress
  # compressed nets) and links it statically. That bundled copy no longer
  # compiles against the current macOS SDK - its gz* sources pull the SDK
  # <stdio.h> in through a patched gzguts.h and clang rejects it. Rather than
  # patch vendored zlib, we drop nixpkgs' own libz.a into the tree where the
  # Makefile expects it. The rule for zlib/libz.a has no prerequisites, so make
  # treats the pre-placed file as up to date and never runs the failing build;
  # the ABI is stable, so the bundled zlib.h decls link cleanly against it.
  buildInputs = [ zlib ];

  enableParallelBuilding = true;

  # We invoke `compile` directly rather than the default target. This is
  # deliberate on two counts:
  #   * it skips the `net` prerequisite, which unconditionally curls the net;
  #   * it skips the default target's PGO pass, which runs `-bench` on the
  #     half-built binary - a build-time execution that breaks reproducibility
  #     and cross-compilation. `compile` is the plain, single-pass build.
  #
  # ARCH=armv8 pins CPU features to the aarch64 baseline (NEON) deterministically
  # instead of ARCH=native, which would compile and run a cputest probe at make
  # parse time. CC/CXX/MYCC come from the Nix toolchain (the Makefile otherwise
  # hardcodes clang/clang++). No EVALFILE is passed, so nothing is embedded and
  # no `ld -b binary` is attempted.
  buildPhase = ''
    runHook preBuild
    # Satisfy the zlib/libz.a prerequisite with nixpkgs' static libz (see above).
    install -Dm644 "${zlib.static}/lib/libz.a" zlib/libz.a
    make compile \
      EXE=${pname} \
      ARCH=${if stdenv.hostPlatform.isAarch64 then "armv8" else "x86-64-avx2"} \
      CC="${stdenv.cc.targetPrefix}cc" \
      CXX="${stdenv.cc.targetPrefix}c++" \
      MYCC="${stdenv.cc.targetPrefix}cc"
    runHook postBuild
  '';

  # Install the binary, and the net beside it under the exact name RubiChess
  # looks for so it is loaded automatically at startup.
  installPhase = ''
    runHook preInstall
    install -Dm755 "${pname}${stdenv.hostPlatform.extensions.executable}" \
      "$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"
    install -Dm644 "${net}" "$out/bin/${netName}"
    runHook postInstall
  '';

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Handshake to uciok, then require a bestmove from `go depth 10`. Because the
  # net is loaded from a file, this doubles as a check that the pinned net is
  # present and compatible: without it RubiChess would answer uci but fail to
  # search. The trailing sleep lets the search finish before `quit`.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"

    out_txt=$(printf 'uci\nquit\n' | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok' to a uci handshake" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "ok: ${pname} speaks UCI"

    search_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 10\n'; \
      sleep 3; printf 'quit\n'; } | $emu "$bin" | tr -d '\r')
    echo "$search_txt" | grep -q '^bestmove ' || {
      echo "FAIL: ${pname} returned no bestmove from 'go depth 10'" >&2
      echo "$search_txt" >&2
      exit 1
    }
    echo "ok: ${pname} searches and returns a bestmove"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "RubiChess, a strong NNUE UCI engine in C++";
    homepage = "https://github.com/Matthies/RubiChess";
    # copying in the repository root is GPL-3.0, and every source header reads
    # "either version 3 of the License, or (at your option) any later version".
    license = licenses.gpl3Plus;
    mainProgram = "rubichess";
    # Unix only for now: the Makefile links nixpkgs' zlib.static (libz.a),
    # which the mingw zlib does not provide (`attribute 'static' missing`), and
    # its net embedding uses GNU-ld `ld -r -b binary`. Gated off Windows until
    # both are handled.
    platforms = platforms.unix;
    maintainers = [ ];
  };
}
