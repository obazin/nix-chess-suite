{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub, fetchurl }:

let
  # Berserk embeds its net via incbin (src/nn/evaluate.c: INCBIN(Embed,
  # EVALFILE)). src/makefile pins MAIN_NETWORK and its `download-network` target
  # curls it from the berserk-networks release. Pin that exact net and pass it
  # as EVALFILE=; because `all` (the target we use) does not depend on
  # download-network, no fetch is attempted at all.
  netFile = "berserk-9b84c340af7e.nn";
  net = fetchurl {
    name = netFile;
    url = "https://github.com/jhonnold/berserk-networks/releases/download/networks/${netFile}";
    hash = "sha256-m4TDQK9+RfbgfwBGI1zLMn9K4IQMjuLEuXuZEh5cUIQ=";
  };
in
mkEngine rec {
  pname = "berserk";
  version = "14";

  src = fetchFromGitHub {
    owner = "jhonnold";
    repo = "berserk";
    rev = version;
    hash = "sha256-UxgKCXNV8NqFlciPKhParq7OwufxeQEUvy0Vz7llI/U=";
  };

  # src/makefile; the Syzygy prober (pyrrhic) and fathom are vendored in-tree,
  # not submodules, so the plain tarball is complete.
  sourceRoot = "source/src";

  # `all` is the plain single-shot compile. `pgo`/`openbench` do a
  # profile-generate/use cycle that works natively but breaks cross, so they
  # are avoided. ARCH is left unset on purpose: the makefile auto-detects
  # arm64 on Apple Silicon (-arch arm64) and falls back to -march=native
  # elsewhere, which mkEngine's sed strips down to a portable baseline.
  makeTarget = "all";

  evalFile = net;
  evalFileName = netFile;

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
    description = "Berserk, a strong NNUE-based UCI chess engine in C by Jay Honnold";
    homepage = "https://github.com/jhonnold/berserk";
    # LICENSE is the verbatim GPLv3 text; source headers (e.g. src/berserk.c)
    # read "version 3 of the License, or (at your option) any later version".
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
