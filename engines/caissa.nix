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
  # Each Caissa release names exactly one net in CMakeLists.txt
  # (DEFAULT_NEURAL_NET_FILE_NAME) and has CMake download it from the
  # Caissa-Nets releases at configure time. Pin that net here instead, so the
  # build never touches the network, and drop it where CMake looks for it;
  # CMake skips its download when the file is already present.
  #
  # The name and hash live in caissa-net.json, not inline, because
  # ci/update-nets.sh rewrites them whenever nix-update moves `version`: the
  # net has to follow the release. Upstream also deletes old net releases
  # (eval-71, pinned for 1.25, is gone), so a stale pin fails to build rather
  # than quietly staying behind.
  netPin = lib.importJSON ./caissa-net.json;
  netFile = "${netPin.name}.pnn";
  net = fetchurl {
    url = "https://github.com/Witek902/Caissa-Nets/releases/download/${netPin.name}/${netFile}";
    inherit (netPin) hash;
  };
in
stdenv.mkDerivation rec {
  pname = "caissa";
  version = "2.0";

  src = fetchFromGitHub {
    owner = "Witek902";
    repo = "Caissa";
    rev = version;
    hash = "sha256-HM6CpFRfbBIs5VlzbP3e/Wz9p/B3seZ5oI5OVEFhmPA=";
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
  # -static: self-contained .exe (nixpkgs' mingw ships libstdc++/libgcc as
  # static+import libs, not shippable DLLs), matching lib/mkEngine.nix.
  env.NIX_CFLAGS_LINK = lib.optionalString stdenv.hostPlatform.isWindows "-static -static-libgcc -static-libstdc++";

  # Build only the engine (and its backend dependency), not the utils/trainer
  # helper binaries — they are training tooling we do not ship and only add
  # failure surface.
  makeFlags = [ "caissa" ];

  postPatch = ''
    # MSVC-style <Windows.h> -> mingw's lowercase <windows.h> (case-sensitive
    # store). mkEngine does this for its engines; Caissa is standalone CMake.
    grep -rlZ '<Windows.h>' --include='*.c' --include='*.cc' --include='*.cpp' --include='*.cxx' --include='*.h' --include='*.hpp' --include='*.hh' --include='*.hxx' . 2>/dev/null \
      | xargs -0 -r sed -i 's/<Windows.h>/<windows.h>/g' || true

    # Refuse to build against a net the source does not ask for, e.g. when the
    # version was bumped but the net pin was not.
    grep -qF 'set(DEFAULT_NEURAL_NET_FILE_NAME ${netFile})' CMakeLists.txt || {
      echo "FAIL: caissa-net.json pins ${netFile}, but CMakeLists.txt names:" >&2
      grep 'DEFAULT_NEURAL_NET_FILE_NAME' CMakeLists.txt >&2 || true
      exit 1
    }

    # Drop the pinned net where CMake expects it; with the file present CMake
    # skips its own download.
    mkdir -p data/neuralNets
    cp ${net} data/neuralNets/${netFile}

    # The CMake path (unlike the Makefile) never defines CAISSA_EVALFILE, so
    # Evaluate.cpp would fall back to loading the net from a file at runtime
    # relative to the CWD — fragile once installed. Define it to the pinned
    # net's absolute in-tree path so INCBIN bakes the net into the binary and
    # the engine is fully self-contained, matching every other engine here.
    substituteInPlace CMakeLists.txt \
      --replace-fail 'add_subdirectory("src")' \
        'add_compile_definitions(CAISSA_EVALFILE="''${CMAKE_SOURCE_DIR}/data/neuralNets/${netFile}")
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
    install -Dm755 bin/caissa${stdenv.hostPlatform.extensions.executable} "$out/bin/caissa${stdenv.hostPlatform.extensions.executable}"
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
