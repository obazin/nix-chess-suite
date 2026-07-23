# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally.
{ lib, stdenv, buildPackages, cmake, windows, fetchFromGitHub, mkEngine ? null }:

# Texel, Peter Österlund's engine — grew out of his earlier CuckooChess and is
# a distinct C++ lineage (not a Stockfish/Fruit fork). It is a CMake project,
# so mkEngine (stdenv + Makefile fixups) does not apply; it is built with a
# plain stdenv.mkDerivation here, mirroring engines/caissa.nix, and held to the
# same UCI-search smoke test as the rest of the collection.
#
# The trained net is committed in-repo as nndata.tbin.compr and embedded at
# build time: lib/texellib/nn/nndata.cpp.in is configured with an absolute
# path to that file, then INCBIN bakes it into the binary
# (INCBIN(NNData, "${NNDATA_FILE}")). Nothing is fetched at build time, so the
# binary is fully self-contained.

stdenv.mkDerivation rec {
  pname = "texel";
  version = "1.12";

  src = fetchFromGitHub {
    owner = "peterosterlund2";
    repo = "texel";
    rev = version;
    hash = "sha256-L+Fd7vDrWrc1g9e+PyEeevop4UW1ZuKciATzrNuasbI=";
  };

  nativeBuildInputs = [ cmake ];
  # winpthreads supplies nanosleep, which libstdc++'s std::this_thread::sleep_for
  # needs on mingw-UCRT (mcfgthreads doesn't provide it).
  buildInputs = lib.optional stdenv.hostPlatform.isWindows windows.pthreads;

  # texel's sysport.h has a MINGW branch (Windows threads); without -DMINGW it
  # falls through __GNUC__ to the POSIX path and fails on <pthread.h>.
  env.NIX_CFLAGS_COMPILE = lib.optionalString stdenv.hostPlatform.isWindows "-DMINGW";

  # The CPU-feature options all default OFF (a portable scalar build). On
  # aarch64 turn on the flags that carry no -march requirement: USE_NEON only
  # adds -DUSE_NEON (armv8-a always has NEON; USE_NEON_DOT, which *would* force
  # -march=armv8.2-a+dotprod, stays off), and USE_CTZ/USE_PREFETCH map to
  # __builtin_ctz / __builtin_prefetch which every target has. On x86_64 keep
  # the portable defaults (no SSE/AVX/BMI2) for reproducibility across CPUs.
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DUSE_PREFETCH=on"
    "-DUSE_CTZ=on"
  ] ++ lib.optionals stdenv.hostPlatform.isAarch64 [
    "-DUSE_NEON=on"
  ];

  # Build only the engine binary, not texelutil/uciadapter/the test suite.
  makeFlags = [ "texel" ];

  # app/texel/CMakeLists sets no RUNTIME_OUTPUT_DIRECTORY, and CMake links the
  # executable to "../../texel" relative to app/texel — i.e. the top of the
  # CMake build dir.
  installPhase = ''
    runHook preInstall
    install -Dm755 texel "$out/bin/texel${stdenv.hostPlatform.extensions.executable}"
    runHook postInstall
  '';

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Embedded-net engine: verify it really searches (returns a bestmove after a
  # real delay), so a net that failed to embed is caught, not just a working
  # UCI handshake.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/texel${stdenv.hostPlatform.extensions.executable}"
    out_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 10\n'; sleep 4; printf 'quit\n'; } \
      | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: texel did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove' || {
      echo "FAIL: texel produced no bestmove (net likely not embedded)" >&2
      echo "$out_txt" >&2; exit 1; }
    echo "ok: texel speaks UCI and searches (net embedded)"
    runHook postInstallCheck
  '';

  enableParallelBuilding = true;

  meta = with lib; {
    platforms = platforms.unix ++ platforms.windows;
    description = "Texel, Peter Österlund's UCI engine (grown from CuckooChess) with a committed, embedded net, built via CMake";
    homepage = "https://github.com/peterosterlund2/texel";
    # COPYING is the verbatim GPLv3 text; source files (e.g. app/texel/texel.cpp)
    # carry the "either version 3 ... or (at your option) any later version"
    # notice, so GPL-3.0-or-later.
    license = licenses.gpl3Plus;
    mainProgram = "texel";
    maintainers = [ ];
  };
}
