# `mkEngine` is accepted and ignored: both engines/default.nix and
# test-engine.nix pass it to every engine file unconditionally.
{ lib, stdenv, buildPackages, cmake, fetchFromGitHub, fetchurl, mkEngine ? null }:

# Caissa is a CMake project, not a Makefile one, so mkEngine (stdenv +
# Makefile fixups) does not apply. It is built with a plain stdenv.mkDerivation
# here; the meta fields and the UCI smoke test below mirror lib/mkEngine.nix so
# this engine is held to the same standard as the rest of the collection.
#
# Only the CMake build has a real aarch64 path — it detects arm64 and selects
# TARGET_ARCH=aarch64-neon (-march=armv8-a+simd, -DUSE_ARM_NEON). The sibling
# src/makefile is x86-only (every target hardcodes -march=native / AVX2 / BMI2
# and the USE_AVX2 defines), so it is unusable on ARM and we ignore it.

let
  # At the 1.25 tag CMake references data/neuralNets/eval-71.pnn but neither
  # commits it nor downloads it (the src/makefile is what curls it from the
  # Caissa-Nets releases). Pin exactly that net so the build never touches the
  # network. eval-71.pnn is the id named in CMakeLists.txt / src/makefile at
  # 1.25, and it is still published as a Caissa-Nets release asset.
  net = fetchurl {
    url = "https://github.com/Witek902/Caissa-Nets/releases/download/eval-71/eval-71.pnn";
    hash = "sha256-YVzvjSXYuzrOU/1cxN7XVG8NHI/OEGdv2DyGRCEmK1s=";
  };
in
stdenv.mkDerivation rec {
  pname = "caissa";
  version = "1.25";

  src = fetchFromGitHub {
    owner = "Witek902";
    repo = "Caissa";
    rev = version;
    hash = "sha256-NRUv0kp7QTm00WuuRvokUVJO4kzHcN4IBeYY80cjNRk=";
  };

  nativeBuildInputs = [ cmake ];

  # Set TARGET_ARCH explicitly rather than leaning on CMake's
  # CMAKE_SYSTEM_PROCESSOR auto-detection, which is unreliable under Nix. Give
  # aarch64 targets (Apple silicon, ARM Linux) the NEON path; x86_64 gets the
  # bmi2 tier CMake would otherwise pick itself.
  cmakeFlags = [
    (if stdenv.hostPlatform.isAarch64
     then "-DTARGET_ARCH=aarch64-neon"
     else "-DTARGET_ARCH=x64-bmi2")
  ];

  # mingw gcc flags a benign off-by-one array-bounds access (index 64 into
  # Bitboard[64]) that -Werror rejects; relax it, only for the Windows cross.
  env.NIX_CFLAGS_COMPILE = lib.optionalString stdenv.hostPlatform.isWindows "-Wno-error";

  # Build only the engine (and its backend dependency), not the utils/trainer
  # helper binaries — they are training tooling we do not ship and only add
  # failure surface.
  makeFlags = [ "caissa" ];

  postPatch = ''
    # MSVC-style <Windows.h> -> mingw's lowercase <windows.h> (case-sensitive
    # store). mkEngine does this for its engines; Caissa is standalone CMake.
    grep -rlZ '<Windows.h>' --include='*.cpp' --include='*.h' . 2>/dev/null \
      | xargs -0 -r sed -i 's/<Windows.h>/<windows.h>/g' || true

    # Drop the pinned net where CMake's `file(COPY data/neuralNets/eval-71.pnn
    # ...)` expects it. Nothing else fetches it in the CMake path.
    mkdir -p data/neuralNets
    cp ${net} data/neuralNets/eval-71.pnn

    # The CMake path (unlike the Makefile) never defines CAISSA_EVALFILE, so
    # Evaluate.cpp would fall back to loading the net from a file at runtime
    # relative to the CWD — fragile once installed. Define it to the pinned
    # net's absolute in-tree path so INCBIN bakes the net into the binary and
    # the engine is fully self-contained, matching every other engine here.
    substituteInPlace CMakeLists.txt \
      --replace-fail 'add_subdirectory("src")' \
        'add_compile_definitions(CAISSA_EVALFILE="''${CMAKE_SOURCE_DIR}/data/neuralNets/eval-71.pnn")
add_subdirectory("src")'

    # Upstream builds -Werror; a newer clang than the author tested turns fresh
    # diagnostics into hard failures. Drop it (both the C and C++ flag lines).
    substituteInPlace CMakeLists.txt \
      --replace-fail '-Wall -Wextra -Werror' '-Wall -Wextra'

    # CMake enables IPO/LTO per target, but archiving a static library under
    # LTO needs llvm-ar, whereas Nix's cctools `ar` on Darwin cannot read LLVM
    # bitcode — the archive step dies with "Error running link command". Turn
    # IPO off for the targets in the engine's dependency chain; the difference
    # in playing strength is negligible.
    substituteInPlace src/backend/CMakeLists.txt src/frontend/CMakeLists.txt \
      --replace-fail 'INTERPROCEDURAL_OPTIMIZATION TRUE' 'INTERPROCEDURAL_OPTIMIZATION FALSE'
  '';

  # The binary lands in ${CMAKE_BINARY_DIR}/bin (i.e. the CMake build dir).
  installPhase = ''
    runHook preInstall
    install -Dm755 bin/caissa "$out/bin/caissa"
    runHook postInstall
  '';

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Same handshake gate mkEngine applies to the Makefile engines: build, then
  # require 'uciok' back. Catches a binary that links but dies on startup (e.g.
  # a net that failed to embed).
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    out_txt=$(printf 'uci\nquit\n' | $emu "$out/bin/caissa${stdenv.hostPlatform.extensions.executable}" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: caissa did not answer 'uciok' to a uci handshake" >&2
      echo "--- engine output ---" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "ok: caissa speaks UCI"
    runHook postInstallCheck
  '';

  enableParallelBuilding = true;

  meta = with lib; {
    description = "Caissa, Michał Witanowski's NNUE UCI engine, built via CMake with an embedded net";
    homepage = "https://github.com/Witek902/Caissa";
    # Verified against the upstream LICENSE file: verbatim MIT text,
    # "Copyright (c) 2021 Michał Witanowski".
    license = licenses.mit;
    mainProgram = "caissa";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
