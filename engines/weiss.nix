{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub }:

mkEngine rec {
  pname = "weiss";
  version = "2.0";

  # Terje Kirstihagen's clean-room engine. NOTE: despite the brief in the task,
  # Weiss 2.0 is NOT NNUE — it ships a hand-crafted (classical) evaluation in
  # src/evaluate.c and there is no net anywhere in the tree and no EVALFILE in
  # the makefile. So there is nothing to pin or thread through EVALFILE=.
  src = fetchFromGitHub {
    owner = "TerjeKir";
    repo = "weiss";
    rev = "v${version}";
    hash = "sha256-dzEH973Tag4NxaRVmpPPOBGq04x03hf7TLi4MFEKRag=";
  };

  sourceRoot = "source/src";

  # `basic` is the plain single-shot unity-style compile (all .c in one CC
  # invocation). `pgo` runs the freshly built binary mid-build to collect a
  # profile, which the sandbox forbids and which breaks cross-compilation, so it
  # is avoided. The Syzygy prober (pyrrhic/tbprobe.c) and NoobBook/online-Syzygy
  # helpers are vendored in-tree, so the plain tarball is complete.
  makeTarget = "basic";
  binaries = [ "weiss" ];

  postPatch = ''
    # -Werror against clang (upstream builds with gcc) turns any new diagnostic
    # into a hard failure. Drop it. The makefile is lowercase 'makefile'.
    substituteInPlace makefile --replace-fail ' -Werror' ""
  '';

  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"
    out_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 10\n'; sleep 4; printf 'quit\n'; } \
      | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove' || {
      echo "FAIL: ${pname} produced no bestmove" >&2; echo "$out_txt" >&2; exit 1; }
    echo "ok: ${pname} speaks UCI and searches"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Weiss 2.0, Terje Kirstihagen's classical UCI chess engine written in C";
    homepage = "https://github.com/TerjeKir/weiss";
    # COPYING.txt is the verbatim GPLv3 text; every source header (e.g.
    # src/evaluate.c) reads "either version 3 of the License, or (at your
    # option) any later version" -> GPL-3.0-or-later.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
