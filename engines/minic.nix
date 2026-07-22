{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub, fetchurl }:

# Minic, Vivien Clauzon's from-scratch C++20 engine (a distinct lineage, not a
# Stockfish/Fruit fork) with its own NNUE. The trained nets live in a separate
# repo (tryingsomestuff/NNUE-Nets); the build embeds one via INCBIN so the
# finished binary is self-contained. Upstream's Tools/build scripts run a full
# PGO cycle, hardcode x86 targets (and, on macOS, an invalid
# `-march=apple-silicon`), and pull the net + Fathom over the network — none of
# which works in the sandbox. We compile the sources directly instead (like
# engines/cheng4.nix), mirroring the plain non-PGO command in
# Tools/build/build.sh, with the net pinned and embedded.

let
  # The default net named in the Makefile (EMBEDDEDNNUENAME=nihilist_nugget.bin,
  # md5 7f72f8f439ae62d1a9503044043607ab — verified against the downloaded
  # file). Pin it at a fixed NNUE-Nets commit rather than the moving master
  # branch the Makefile curls from.
  net = fetchurl {
    name = "nihilist_nugget.bin";
    # NNUE-Nets stores nets in Git LFS. raw.githubusercontent.com serves only
    # the 134-byte LFS *pointer*; the actual 151 MB net is at the media
    # endpoint. (A local build can pass on a raw-URL pin if the real net is
    # already cached in the store, but a clean CI fetch gets the pointer and
    # fails the fixed-output hash — hence the media URL.)
    url = "https://media.githubusercontent.com/media/tryingsomestuff/NNUE-Nets/9a32a4c1727a87ab05be4495f2baf8fc57b11e75/nihilist_nugget.bin";
    hash = "sha256-zZxp0K2FmPSVzXyhunBAoG3WofJ77GFOEV75xemX6ZY=";
  };
in
mkEngine rec {
  pname = "minic";
  version = "3.46";

  src = fetchFromGitHub {
    owner = "tryingsomestuff";
    repo = "Minic";
    rev = "1e7c0ecb31e06e4bd80d14e529c3dcf01d120c2f";
    hash = "sha256-uiSDoLi9N897Jas6TTdmvTdxPHui5vz3pJbIl8O58Lk=";
  };

  # We drive the compiler ourselves; nothing here is arch-flag-bearing to strip.
  stripArchFlags = false;

  postPatch = ''
    # WITH_SYZYGY (on by default) makes egt.cpp include Fathom's tbprobe.h,
    # which lives in a git submodule the sandbox cannot fetch. Disable it; the
    # engine plays fine without tablebase probing. Everything else stays as-is.
    substituteInPlace Source/config.hpp \
      --replace-fail '#define WITH_SYZYGY' '//#define WITH_SYZYGY'

    # The RAPL energy monitor opens directory_iterator("/sys/class/powercap")
    # unconditionally at search start. That Linux-only path is absent on macOS
    # (and in the sandbox), and directory_iterator on a missing path THROWS
    # filesystem_error, which crashes the engine on the first `go`. Guard the
    # scan with an existence check so it simply reports no RAPL domains instead.
    substituteInPlace Source/energyMonitor.cpp \
      --replace-fail \
        'for (const auto& p : std::filesystem::directory_iterator("/sys/class/powercap")) {' \
        'if (!std::filesystem::exists("/sys/class/powercap")) return out;
   for (const auto& p : std::filesystem::directory_iterator("/sys/class/powercap")) {'
  '';

  # Mirror Tools/build/build.sh's non-PGO branch (NOPROFILE): the same source
  # set (Source plus the nnue and nnue/learn trees), the same C++20 / -O3
  # release flags and -fopenmp-simd, minus the PGO instrumentation, the invalid
  # macOS -march, and Fathom. The net is embedded straight from its store path:
  # nnueImpl.cpp does INCBIN(weightsFile, INCBIN_STRINGIZE(EMBEDDEDNNUEPATH)),
  # so pointing EMBEDDEDNNUEPATH at the pinned file bakes it in (FORCEEMBEDDEDNNUE
  # also short-circuits the Makefile's net-download path, which we never run).
  # No -march is passed, so clang targets the host baseline; the NNUE SIMD layer
  # (Source/nnue/simd.hpp) guards every x86 intrinsic behind __SSE__/__AVX__ and
  # falls back to scalar code on aarch64. LTO/PGO are intentionally omitted for
  # portability and build reproducibility.
  buildPhase = ''
    runHook preBuild
    $CXX -O3 -DNDEBUG -fno-math-errno -funroll-loops -fno-exceptions \
      -fopenmp-simd -std=c++20 -DDEBUG_TOOL \
      -DFORCEEMBEDDEDNNUE '-DEMBEDDEDNNUEPATH=${net}' \
      -ISource -ISource/nnue \
      Source/*.cpp Source/nnue/*.cpp Source/nnue/learn/*.cpp \
      -o minic -lpthread
    runHook postBuild
  '';

  binaries = [ "minic" ];

  # Embedded-net engine: verify a real search returns a bestmove, so a net that
  # failed to embed is caught rather than only the UCI handshake.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"
    out_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 10\n'; sleep 4; printf 'quit\n'; } \
      | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove' || {
      echo "FAIL: ${pname} produced no bestmove (NNUE net likely not embedded)" >&2
      echo "$out_txt" >&2; exit 1; }
    echo "ok: ${pname} speaks UCI and searches (net embedded)"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Minic, Vivien Clauzon's from-scratch C++20 NNUE UCI engine with a pinned, embedded net";
    homepage = "https://github.com/tryingsomestuff/Minic";
    # LICENSE is the verbatim GPLv3 text. The source files carry no per-file
    # "or any later version" notice and the README states no version, so the
    # conservative reading is GPL-3.0-only.
    license = licenses.gpl3Only;
    mainProgram = "minic";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
