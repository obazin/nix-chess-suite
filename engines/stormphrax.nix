{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub, fetchurl, clang }:

let
  # Stormphrax picks its net by name from network.txt ("undertown"); the top
  # Makefile curls $NET.nnue from the stormphrax-nets release. Pin that exact
  # file and pass it as EVALFILE=. On the command line EVALFILE also trips the
  # Makefile's `ifndef EVALFILE` guard, so the download recipe is never defined.
  #
  # Note the net is not embedded directly: build.mk first compiles a small
  # `permute` preprocessor (preprocess/permute.cpp), runs it on the pinned net
  # to produce a permuted copy, and incbins that. That native helper runs fine
  # here (aarch64-darwin building aarch64-darwin); it would need care under
  # cross-compilation.
  netName = "undertown";
  netFile = "${netName}.nnue";
  net = fetchurl {
    name = netFile;
    url = "https://github.com/Ciekce/stormphrax-nets/releases/download/${netName}/${netFile}";
    hash = "sha256-BNZR4Hi3xzNHCdvXctQKI8ClSA6T4ZUhoDAgx9Yz8s8=";
  };
in
mkEngine rec {
  pname = "stormphrax";
  version = "8.0.0";

  src = fetchFromGitHub {
    owner = "Ciekce";
    repo = "Stormphrax";
    rev = "v${version}";
    hash = "sha256-uXwRzsxk8gbYk6vlofN9cEnnewfPPUy8qJPysAzmGAM=";
  };

  # fmt, zstd and pyrrhic are all vendored under 3rdparty/ (no submodules).
  # Makefile is at the repo root, which is where EVALFILE is resolved.
  evalFile = net;
  evalFileName = netFile;

  # Stormphrax has no PGO target; `native` is the standard build. stripArchFlags
  # is off only to keep mkEngine's blanket sed away from build.mk's own arch
  # matrix — the -march=native it carries is neutralised anyway by the Nix
  # cc-wrapper (NIX_ENFORCE_NO_NATIVE), which drops it and leaves a portable
  # baseline aarch64 build that compiles and searches cleanly (verified). Under
  # real cross-compilation a fixed -march (e.g. the armv8-4 target) would be
  # needed instead.
  stripArchFlags = false;
  makeTarget = "native";

  # EXE= gives a clean binary name (default is stormphrax-$(VERSION)-native).
  # build.mk hard-requires a clang whose `--version` says "clang"; mkEngine's
  # CC=cc/CXX=c++ satisfy that on Darwin.
  makeFlags = [ "EXE=stormphrax" ];
  binaries = [ "stormphrax" ];

  # build.mk hard-errors unless the compiler's --version says "clang". Darwin's
  # stdenv cc already is clang; the Linux stdenv is gcc, which trips the check
  # (and the tab-indented $(error) even manifests as a Make parse error). On
  # Linux, provide clang and force build.mk to use it via `override` (which
  # beats the CC=/CXX= mkEngine passes on the command line).
  nativeBuildInputs = lib.optional stdenv.hostPlatform.isLinux clang;

  postPatch = lib.optionalString stdenv.hostPlatform.isLinux ''
    substituteInPlace build.mk \
      --replace-fail 'LDFLAGS :=' 'override CC := clang
override CXX := clang++
LDFLAGS :='
  '';

  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"
    out_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 12\n'; sleep 3; printf 'quit\n'; } \
      | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove' || {
      echo "FAIL: ${pname} produced no bestmove (NNUE net likely not loaded)" >&2
      echo "$out_txt" >&2; exit 1; }
    echo "ok: ${pname} speaks UCI and searches (net loaded)"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Stormphrax, a strong NNUE-based UCI chess engine in C++ by Ciekce";
    homepage = "https://github.com/Ciekce/Stormphrax";
    # LICENSE is the verbatim GPLv3 text; source headers (e.g. src/main.cpp)
    # read "version 3 of the License, or (at your option) any later version".
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
