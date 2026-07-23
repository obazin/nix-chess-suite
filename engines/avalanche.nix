# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally. Avalanche is written in Zig, so
# mkEngine (stdenv.mkDerivation + Makefile fixups for C engines) does not apply.
# This is a plain stdenv.mkDerivation driving `zig build` directly. The meta
# fields and the UCI smoke test below mirror lib/mkEngine.nix so the engine is
# held to the same standard as the rest of the collection.
{ lib, stdenv, buildPackages, fetchFromGitHub, zig_0_16, mkEngine ? null }:

# Avalanche is the first competitive chess engine written in Zig. It pins an
# EXACT Zig toolchain: as of the June 2026 rewrite it builds only with Zig
# 0.16.0 (Zig routinely makes breaking changes across minor releases, so this
# is not negotiable). The pinned nixpkgs happens to ship zig_0_16 = 0.16.0
# exactly, so no toolchain gymnastics are needed.
#
# The NNUE net is committed in-repo (nets/*.nnue) and pulled in with Zig's
# @embedFile via build.zig's `-Dnet` option (default nets/jihan83.nnue), so
# unlike most modern engines there is NO net to fetch and pin separately, and
# build.zig.zon is absent so there are no network-fetched Zig dependencies
# either: the build is fully hermetic from the source tree alone.
stdenv.mkDerivation rec {
  pname = "avalanche";
  version = "3.0.0";

  src = fetchFromGitHub {
    owner = "SnowballSH";
    repo = "Avalanche";
    rev = "v${version}";
    hash = "sha256-Vq3mYAK9jOs9idrnw3peZPFHqr85kaNycV3C2B/GhFU=";
  };

  nativeBuildInputs = [ zig_0_16 ];

  # Zig insists on a writable global cache and a HOME; the sandbox provides
  # neither by default. Point both at the build's temp dir. `--release=fast`
  # is Zig 0.16's spelling of ReleaseFast (upstream's recommended build).
  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    zig build --release=fast --prefix "$TMPDIR/zig-out"
    runHook postBuild
  '';

  # build.zig installs the artifact as `Avalanche` (capitalised). Install it
  # under that name and add a lowercase `avalanche` alias so mainProgram and
  # the smoke test resolve.
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    install -Dm755 "$TMPDIR/zig-out/bin/Avalanche${stdenv.hostPlatform.extensions.executable}" \
      "$out/bin/avalanche${stdenv.hostPlatform.extensions.executable}"
    runHook postInstall
  '';

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Same guarantee as mkEngine, plus a real search: handshake to uciok, then
  # require a bestmove from `go depth 8`. Quitting immediately would cancel the
  # search and yield a false failure, so we sleep before sending quit. A missing
  # or unreadable embedded net passes the handshake but dies on `go`, so this
  # also proves the @embedFile'd net loaded.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"

    out_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 8\n'; \
      sleep 4; printf 'quit\n'; } | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok' to a uci handshake" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "$out_txt" | grep -q '^bestmove ' || {
      echo "FAIL: ${pname} returned no bestmove from 'go depth 8'" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "ok: ${pname} speaks UCI and searches (embedded net loaded)"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Avalanche, a strong NNUE UCI chess engine and the first written in Zig";
    homepage = "https://github.com/SnowballSH/Avalanche";
    # LICENSE in the repo root is the verbatim MIT text, "Copyright (c) 2026
    # Yinuo Huang". https://github.com/SnowballSH/Avalanche/blob/master/LICENSE
    license = licenses.mit;
    mainProgram = "avalanche";
    # Gated off Windows: Zig cross to Windows needs a libc install nixpkgs zig lacks here.
    platforms = platforms.unix;
    maintainers = [ ];
  };
}
