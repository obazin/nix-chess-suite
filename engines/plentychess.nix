# PlentyChess is a C++ Makefile project, but its net handling is a two-stage
# process (build a host-native preprocessor, run it on the raw net, embed the
# result) that mkEngine does not model, so this is a standalone derivation. The
# meta fields and the UCI smoke test below mirror lib/mkEngine.nix.
#
# `mkEngine` is accepted and ignored so callPackage can pass it uniformly.
{ lib, stdenv, buildPackages, fetchFromGitHub, fetchurl, windows, mkEngine ? null }:

let
  # Raw NNUE net. network.txt in the pinned tree names net "0178r"; the Makefile
  # would curl it from Yoshie2000/PlentyNetworks at build time, which the sandbox
  # forbids. Pin it as a fetchurl and hand it to the build as EVALFILE.
  net = fetchurl {
    url = "https://github.com/Yoshie2000/PlentyNetworks/releases/download/0178r/0178r.bin";
    hash = "sha256-Zj4FMaxxxsfG07xPH6ySO/aRNvl4b6HaXErCU4Ku5Us=";
  };
in
# On the Windows cross, POSIX threads come from winpthreads.
stdenv.mkDerivation rec {
  pname = "plentychess";
  version = "8.0.0";

  src = fetchFromGitHub {
    owner = "Yoshie2000";
    repo = "PlentyChess";
    rev = "b-v${version}";
    hash = "sha256-jVzFvCrVV6VhPYbR+PsTGO3EW0leN0QUweyAQwXakLY=";
  };

  enableParallelBuilding = true;

  # Two-stage net embedding. `make all` first runs the `process-net` target,
  # which builds tools/process_net for the BUILD machine and runs it to turn the
  # raw net into ./processed.bin, then compiles the engine with that file
  # embedded via incbin. Because we build natively (build == host) the helper
  # runs directly; a cross build would need an emulator for this step.
  #
  # Key overrides:
  #   * EVALFILE=<pinned net> makes `process-net` skip its curl and process the
  #     pinned raw net instead (setting EVALFILE also disables the download path
  #     in the Makefile entirely).
  #   * CXX/CC come from the Nix toolchain. This matters twice: the main Makefile
  #     hardcodes clang++, and tools/Makefile hardcodes g++ (absent in the
  #     sandbox) - a command-line CXX propagates to the `-C tools` sub-make too.
  #   * EXE=plentychess selects the release path (-DNDEBUG) and names the binary.
  #
  # No arch-flag stripping is needed: on arm64 the Makefile picks
  # -march=armv8-a+simd -DARCH_ARM and emits no x86-only flags.
  buildPhase = ''
    runHook preBuild
    make all \
      EXE=${pname} \
      CXX="${stdenv.cc.targetPrefix}c++" \
      CC="${stdenv.cc.targetPrefix}cc" \
      EVALFILE=${net}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 "${pname}${stdenv.hostPlatform.extensions.executable}" \
      "$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"
    runHook postInstall
  '';

  buildInputs = lib.optional stdenv.hostPlatform.isWindows windows.pthreads;
  NIX_LDFLAGS = lib.optionalString stdenv.hostPlatform.isWindows "-lpthread";

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Handshake to uciok, then require a bestmove from `go depth 10`. The net is
  # embedded, so a search failure here would mean a broken embed, not a missing
  # file. The trailing sleep lets the search finish before `quit`.
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
    description = "PlentyChess, a strong NNUE UCI engine in C++";
    homepage = "https://github.com/Yoshie2000/PlentyChess";
    # LICENSE in the repository root is the verbatim GNU GPL-3.0 text.
    license = licenses.gpl3Only;
    mainProgram = "plentychess";
    # Gated off Windows: its two-stage net preprocessor (process_net) is built
    # for the host and cannot run on the Linux build machine (as with alexandria).
    platforms = platforms.unix;
    maintainers = [ ];
  };
}
