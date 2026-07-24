# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally.
{ lib, stdenv, buildPackages, cmake, fetchFromGitHub, windows, mkEngine ? null }:

# Vajolet2, Marco Belli's from-scratch C++ engine (a distinct lineage, not a
# Stockfish/Fruit fork). CMake project, so it is built with a plain
# stdenv.mkDerivation here rather than through mkEngine, mirroring
# engines/caissa.nix and held to the same UCI-search smoke test.
#
# The trained net is committed in-repo at NN/nnue.par and embedded at build
# time: src/nnue/nnue.cpp does INCBIN(NnueInternalFile, "../../NN/nnue.par"),
# which the compiler resolves relative to that source file (-> repo-root
# NN/nnue.par). Nothing is fetched at build time, so the binary is
# self-contained.

stdenv.mkDerivation rec {
  pname = "vajolet2";
  version = "3.2";

  src = fetchFromGitHub {
    owner = "elcabesa";
    repo = "vajolet";
    # The v3.2 tree; the repo's tag is "Vajole2_3.2". Pin the commit directly.
    rev = "ab0ce1ed70f543382ad6f6051ec4b1c8b288b641";
    hash = "sha256-FWy9qW8igAiBim/gL5ii74xQkWMtMtpsD8jnGy/+AMg=";
  };

  nativeBuildInputs = [ cmake ];

  # Leave VAJOLET_CPU_TYPE unset so the CMakeLists CPU branch falls through to
  # its empty ELSE(): no -msse*/-mbmi2/-mavx2 flags are added, giving a
  # portable build that compiles on aarch64. (The 64OLD/64NEW/64BMI2 tiers are
  # all x86-only.) VAJOLET has no x86 intrinsics — popcount goes through
  # __builtin_popcountll (clang provides it on aarch64), so no popcount
  # fallback patch is needed.
  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];

  # Build only the engine target, not the gtest-based test suite or the tuner.
  makeFlags = [ "Vajolet" ];

  postPatch = ''
    # The root CMakeLists unconditionally FetchContent-downloads GoogleTest at
    # configure time (forbidden in the sandbox) purely to build tests/ and
    # tuner/. Strip the FetchContent block and those two subdirectories, keeping
    # only the engine (add_subdirectory(src)).
    sed -i -e '/^include(FetchContent)/,/^add_subdirectory(tuner)/d' CMakeLists.txt
    echo 'add_subdirectory(src)' >> CMakeLists.txt

    # `-s` (strip at link) is obsolete on Darwin's linker and errors on recent
    # cctools; drop it from the Release flags.
    substituteInPlace CMakeLists.txt \
      --replace-fail ' -O3 -DNDEBUG -s' ' -O3 -DNDEBUG'

    # The non-Windows link flags use GNU-ld-only options (`-static`,
    # `-Wl,--whole-archive`/`--no-whole-archive`) that Apple's ld64 rejects, and
    # a fully static link is unsupported on Darwin anyway. Neutralise them; on
    # this toolchain libpthread is part of libc, so nothing else is required.
    substituteInPlace CMakeLists.txt \
      --replace-quiet '-Wl,--whole-archive' "" \
      --replace-quiet '-Wl,--no-whole-archive' "" \
      --replace-quiet '-static' ""
  '';

  # add_executable(Vajolet ...) lives in src/, so CMake emits the binary at
  # ${CMAKE_BINARY_DIR}/src/Vajolet.
  installPhase = ''
    runHook preInstall
    install -Dm755 src/Vajolet${stdenv.hostPlatform.extensions.executable} "$out/bin/vajolet2${stdenv.hostPlatform.extensions.executable}"
    runHook postInstall
  '';

  buildInputs = lib.optional stdenv.hostPlatform.isWindows windows.pthreads;
  # -static: self-contained .exe (nixpkgs' mingw ships libstdc++/libgcc as
  # static+import libs, not shippable DLLs), matching lib/mkEngine.nix.
  NIX_LDFLAGS = lib.optionalString stdenv.hostPlatform.isWindows "-static -static-libgcc -static-libstdc++ -lpthread";

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Embedded-net engine: verify a real search returns a bestmove, so a net that
  # failed to embed is caught rather than only the UCI handshake.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/vajolet2${stdenv.hostPlatform.extensions.executable}"
    out_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 10\n'; sleep 4; printf 'quit\n'; } \
      | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: vajolet2 did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove' || {
      echo "FAIL: vajolet2 produced no bestmove (net likely not embedded)" >&2
      echo "$out_txt" >&2; exit 1; }
    echo "ok: vajolet2 speaks UCI and searches (net embedded)"
    runHook postInstallCheck
  '';

  enableParallelBuilding = true;

  meta = with lib; {
    description = "Vajolet2, Marco Belli's from-scratch NNUE UCI engine with a committed, embedded net, built via CMake";
    homepage = "https://github.com/elcabesa/vajolet";
    # copying.txt is the verbatim GPLv3 text; src/vajolet.cpp carries the
    # "either version 3 ... or (at your option) any later version" notice.
    license = licenses.gpl3Plus;
    mainProgram = "vajolet2";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
