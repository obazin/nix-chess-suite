{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub, fetchurl }:

let
  # Stockfish ships TWO nets since SF16: a big net used in most positions and a
  # small net used in simple/endgame positions. Both are embedded into the
  # binary at build time via incbin; the Makefile's `net` target normally
  # curls them from the network, which the Nix sandbox forbids.
  #
  # The exact filenames are the source of truth in src/evaluate.h:
  #   #define EvalFileDefaultNameBig   "nn-c288c895ea92.nnue"
  #   #define EvalFileDefaultNameSmall "nn-37f18f62d772.nnue"
  # Each is pinned as its own fetchurl and copied into src/ before the build,
  # so scripts/net.sh finds them already present, validates the sha256 embedded
  # in the filename, and skips the download entirely. Same approach nixpkgs'
  # own stockfish derivation uses.
  nnueBigFile = "nn-c288c895ea92.nnue";
  nnueBig = fetchurl {
    name = nnueBigFile;
    url = "https://tests.stockfishchess.org/api/nn/${nnueBigFile}";
    hash = "sha256-wojIleqSRCnqkJLj82srPB8A8qOkx1n/flfnnjtD5Kc=";
  };

  nnueSmallFile = "nn-37f18f62d772.nnue";
  nnueSmall = fetchurl {
    name = nnueSmallFile;
    url = "https://tests.stockfishchess.org/api/nn/${nnueSmallFile}";
    hash = "sha256-N/GPYtdy8xB+HWqso4mMEww8hvKrY+ZVX7vKIGNaiZ0=";
  };

  # Stockfish's Makefile has a proper arch matrix; feed it the right target
  # rather than letting mkEngine's blanket arch-flag sed loose on it.
  arch =
    if stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64 then "apple-silicon"
    else if stdenv.hostPlatform.isx86_64 then "x86-64"
    else if stdenv.hostPlatform.isAarch64 then "armv8"
    else "general-64";
in
mkEngine rec {
  pname = "stockfish";
  version = "18";

  src = fetchFromGitHub {
    owner = "official-stockfish";
    repo = "Stockfish";
    rev = "sf_${version}";
    hash = "sha256-J9E0fJeUemKh1mAPJ5PjZ3kmXqAc1Ec3dG5sfzvhuGo=";
  };

  sourceRoot = "source/src";

  # Stockfish owns its codegen flags via ARCH=; the generic sed would corrupt
  # its arch matrix.
  stripArchFlags = false;

  # `build` is the plain (non-PGO) target. The PGO target here is
  # `profile-build`, which we deliberately avoid: it works natively but breaks
  # under cross-compilation, and correctness matters more than peak nps.
  makeTarget = "build";
  makeFlags = [ "ARCH=${arch}" ];

  binaries = [ "stockfish" ];

  # Place both pinned nets where scripts/net.sh (run by the `net` prerequisite
  # of `build`) expects them, so no network fetch is attempted. mkEngine's
  # single-net evalFile mechanism can't express two nets, so this is done by
  # hand.
  postUnpack = ''
    cp ${nnueBig} "$sourceRoot/${nnueBigFile}"
    cp ${nnueSmall} "$sourceRoot/${nnueSmallFile}"
  '';

  # Beyond the uciok handshake, drive a real search: a build with a missing or
  # broken net typically answers uciok and then dies on `go`. Require a
  # bestmove back to prove the embedded net actually loaded.
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
    description = "Stockfish 18, the strongest open-source UCI chess engine, NNUE-based";
    homepage = "https://stockfishchess.org/";
    # Copying.txt is the verbatim GPLv3 text; every source header (e.g.
    # src/types.h) reads "version 3 of the License, or (at your option) any
    # later version", i.e. GPL-3.0-or-later. The nets in
    # official-stockfish/networks are distributed under the same GPLv3.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
