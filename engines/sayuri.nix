# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally.
{ lib, stdenv, buildPackages, cmake, fetchFromGitHub, mkEngine ? null }:

# Sayuri — Hironori Ishibashi's quirky C++11 engine, notable for embedding a
# Scheme dialect ("Sayulisp") that can script and reconfigure the engine. Run
# with no arguments it is an ordinary UCI engine; a script argument switches it
# into interpreter mode. A CMake project, so it is built with a plain
# stdenv.mkDerivation here rather than through mkEngine, mirroring
# engines/vajolet2.nix and held to the same UCI-search smoke test.
#
# Everything the engine needs (including the Sayulisp core) is compiled from
# src/*.cpp — no nets, no data files, nothing fetched at build time.

stdenv.mkDerivation rec {
  pname = "sayuri";
  # Upstream is untagged; the CMakeLists carries VERSION "2018.05.23", which
  # matches the pinned head commit.
  version = "2018.05.23";

  src = fetchFromGitHub {
    owner = "MetalPhaeton";
    repo = "sayuri";
    rev = "27a65bc2c2a9be49d394fbc9abbe50ad91dfa718";
    hash = "sha256-3hd34AG/62PrNnjV0c3dOyduBdh4BUnyJE3la0PFqE8=";
  };

  nativeBuildInputs = [ cmake ];

  postPatch = ''
    # ARCH_OPTION defaults to -march=native, which Apple clang does not accept
    # on aarch64 and which would pin the build to the builder's CPU anyway.
    # Blank it for a portable build (Sayuri has no x86 intrinsics; popcount
    # goes through the compiler builtin).
    substituteInPlace CMakeLists.txt \
      --replace-fail 'set(ARCH_OPTION "-march=native")' 'set(ARCH_OPTION "")'

    # Drop -fno-rtti. Sayuri's thread management deliberately calls join() on a
    # not-yet-started std::thread on the first `go` and relies on catching the
    # resulting std::system_error (EINVAL). Under libc++ on Darwin the exception
    # is thrown from the dylib, and with -fno-rtti the user-code catch clause
    # fails to match its type, so the "expected" exception escapes and aborts
    # the process the instant a search starts. Keeping RTTI makes the catch
    # match and the engine search normally; the codebase uses no typeid/
    # dynamic_cast, so nothing else depends on the flag.
    substituteInPlace CMakeLists.txt \
      --replace-fail '-fexceptions -fno-rtti' '-fexceptions'
  '';

  # CMakeLists sets CMAKE_C(XX)_COMPILER to clang/clang++ only when unset;
  # pin them to the Nix toolchain wrappers explicitly so the stdenv compiler is
  # used. install(TARGETS sayuri DESTINATION bin) drops the binary in $out/bin,
  # so the default cmake installPhase needs no override.
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_C_COMPILER=cc"
    "-DCMAKE_CXX_COMPILER=c++"
    # CMakeLists declares cmake_minimum_required(VERSION 2.8); modern CMake
    # (>=4) refuses < 3.5 compatibility. Opt back in — the project is a trivial
    # single add_executable that needs no old-policy behaviour.
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
  ];

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Full handshake-plus-search check: require an actual bestmove so a broken
  # search (not just a missing uciok) is caught. Sayuri exits on quit.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/sayuri${stdenv.hostPlatform.extensions.executable}"

    out_txt=$( { printf 'uci\n';              sleep 0.5; \
                 printf 'isready\n';           sleep 0.5; \
                 printf 'position startpos\n'; sleep 0.5; \
                 printf 'go depth 10\n';       sleep 5; \
                 printf 'quit\n';              sleep 0.5; } \
               | timeout -s KILL 30 $emu "$bin" 2>/dev/null | tr -d '\r' || true)

    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: sayuri did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove ' || {
      echo "FAIL: sayuri returned no bestmove from 'go depth 10'" >&2
      echo "$out_txt" >&2; exit 1; }
    echo "ok: sayuri speaks UCI and searches"
    runHook postInstallCheck
  '';

  enableParallelBuilding = true;

  meta = with lib; {
    description = "Sayuri, Hironori Ishibashi's C++11 UCI engine with an embedded 'Sayulisp' Scheme interpreter";
    homepage = "https://github.com/MetalPhaeton/sayuri";
    # LICENSE in the repo root is verbatim MIT,
    # "Copyright (c) 2013-2017 Hironori Ishibashi"; the same notice heads
    # CMakeLists.txt and the sources.
    # https://github.com/MetalPhaeton/sayuri/blob/master/LICENSE
    license = licenses.mit;
    mainProgram = "sayuri";
    # Gated off Windows: CMake project doesn't configure for the mingw cross.
    platforms = platforms.unix;
    maintainers = [ ];
  };
}
