{ lib, stdenv, buildPackages, cmake, fetchFromGitHub, fetchurl, mkEngine ? null }:

# Igel is a CMake project, not a Makefile one, so mkEngine (stdenv + Makefile
# fixups) does not apply; it is built with a plain stdenv.mkDerivation, and the
# meta/smoke-test mirror lib/mkEngine.nix. Igel is Volodymyr Shcherbyna's engine
# — a DISTINCT TCEC lineage, unrelated to any other engine here.
#
# IMPORTANT PLATFORM CAVEAT (same situation as obsidian.nix)
# Igel is x86_64-only. src/nnue.h includes <immintrin.h> UNCONDITIONALLY and
# src/nnue.cpp is written entirely against AVX/SSE intrinsics (_mm256_*, __m256i,
# ~50 uses) with NO NEON or scalar fallback on the 3.6.0 tag or on master.
# Building for aarch64 therefore fails at the first #include with
#   immintrin.h: "This header is only meant to be used on x86 and x64".
# meta.platforms is restricted to x86_64 accordingly, so the flake skips it on
# this repo's aarch64-darwin host. As with obsidian, this file is NOT
# build-verified: the only Nix host available here is aarch64-darwin, where Igel
# is unbuildable by design. The net pin is verified (the fetchurl resolves) and
# the x86 CMake wiring is best-effort — it should be checked on an x86_64-linux
# runner before being relied upon.

let
  # Igel embeds the net via INCBIN(EmbeddedNNUE, EVALFILE) in src/nnue.cpp, and
  # the net is a release asset OF THE IGEL REPO ITSELF. The 3.6.0 README's build
  # recipe pins exactly this file — `wget .../releases/download/3.5.0/c049c117
  # -O network_file; cmake -DEVALFILE=network_file ...` — so c049c117 (published
  # under the 3.5.0 release) is the net 3.6.0 is built and tested against. We
  # pin that asset and hand its absolute store path to CMake as EVALFILE, so the
  # build never touches the network and the net is baked into the binary.
  net = fetchurl {
    name = "igel-network_file-c049c117";
    url = "https://github.com/vshcherbyna/igel/releases/download/3.5.0/c049c117";
    hash = "sha256-1RPzt51WbQuyUTaxI5eKLg/LAifSIQBI9D6w6HkZffM=";
  };
in
stdenv.mkDerivation rec {
  pname = "igel";
  version = "3.6.0";

  src = fetchFromGitHub {
    owner = "vshcherbyna";
    repo = "igel";
    rev = version;
    hash = "sha256-24WVuGDE7/PP3YYVEnOAFBDfl27WMOcKOmn9ELm0cko=";
    # external/googletest is a submodule, but it is only referenced by the
    # _MAKE_UNIT_TEST CMake branch, which we do not enable, so it is left
    # unfetched deliberately.
  };

  nativeBuildInputs = [ cmake ];

  # Mirror the upstream 3.6.0 release recipe: embed the pinned net, enable the
  # AVX2 NNUE path and the BMI2 (_BTYPE=1 -> -mbmi2) build tier, and compile in
  # Syzygy (fathom) support. The CMakeLists' -march=native is replaced below
  # with a fixed x86-64-v3 baseline for reproducibility across CPUs.
  cmakeFlags = [
    "-DEVALFILE=${net}"
    "-DUSE_AVX2=1"
    "-D_BTYPE=1"
    "-DSYZYGY_SUPPORT=TRUE"
  ];

  postPatch = ''
    # -march=native pins the build to whatever CPU built it, breaking
    # reproducibility; x86-64-v3 is the portable AVX2+BMI2 baseline the NNUE
    # code requires. -Werror turns fresh diagnostics from a newer compiler than
    # the author tested into hard failures, so drop it.
    substituteInPlace CMakeLists.txt \
      --replace-fail '-march=native' '-march=x86-64-v3' \
      --replace-fail '-Wall -Werror -O3' '-Wall -O3'

    # gen.cpp calls std::replace but includes only <chrono>/<thread>; newer gcc
    # no longer pulls <algorithm> in transitively. Add it.
    substituteInPlace src/gen.cpp \
      --replace-fail '#include "gen.h"' '#include "gen.h"
#include <algorithm>'
  '';

  # CMake builds out-of-tree in the Nix build dir; the `igel` executable lands
  # there, so install it directly.
  installPhase = ''
    runHook preInstall
    install -Dm755 igel "$out/bin/igel${stdenv.hostPlatform.extensions.executable}"
    runHook postInstall
  '';

  # Only runs where the target can execute (x86_64 Linux CI); the aarch64-darwin
  # host here cannot, so doInstallCheck is false and the build is skipped, not
  # falsely passed. Igel is NNUE, so the check verifies a real search: a missing
  # or incompatible net passes the handshake but produces no bestmove.
  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/igel${stdenv.hostPlatform.extensions.executable}"

    out_txt=$(printf 'uci\nquit\n' | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: igel did not answer 'uciok' to a uci handshake" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "ok: igel speaks UCI"

    search_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 10\n'; \
      sleep 4; printf 'quit\n'; } | $emu "$bin" | tr -d '\r')
    echo "$search_txt" | grep -q '^bestmove ' || {
      echo "FAIL: igel returned no bestmove (NNUE net likely not embedded)" >&2
      echo "$search_txt" >&2
      exit 1
    }
    echo "ok: igel searches and returns a bestmove (net loaded)"
    runHook postInstallCheck
  '';

  enableParallelBuilding = true;

  meta = with lib; {
    description = "Igel, Volodymyr Shcherbyna's NNUE UCI engine (x86_64 only)";
    homepage = "https://github.com/vshcherbyna/igel";
    # Verified from primary evidence: the upstream LICENSE is verbatim GNU
    # GPL-3.0 text, and every source header (e.g. src/main.cpp) reads "either
    # version 3 of the License, or (at your option) any later version", i.e.
    # GPL-3.0-or-later.
    license = licenses.gpl3Plus;
    mainProgram = "igel";
    # x86_64-only: the NNUE code has no ARM SIMD path. See the header comment.
    platforms = [ "x86_64-linux" "x86_64-windows" ];
    maintainers = [ ];
  };
}
