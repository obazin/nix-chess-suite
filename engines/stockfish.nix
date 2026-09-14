{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub, fetchurl }:

let
  # SF19 dropped the dual big/small net architecture from SF16-18 and went
  # back to a single net, embedded via incbin. The exact filename is the
  # source of truth in src/evaluate.h:
  #   #define EvalFileDefaultName "nn-1a298aa575a0.nnue"
  # Pinned as its own fetchurl and copied into src/ before the build via
  # mkEngine's evalFile mechanism, so scripts/net.sh (run by the `net`
  # prerequisite of `build`) finds it already present, validates the sha256
  # embedded in the filename, and skips the network fetch entirely — which
  # the Nix sandbox forbids anyway. Same approach nixpkgs' own stockfish
  # derivation uses.
  netFile = "nn-1a298aa575a0.nnue";
  net = fetchurl {
    name = netFile;
    url = "https://tests.stockfishchess.org/api/nn/${netFile}";
    hash = "sha256-GimKpXWghUNNKQJ5eNw2hn/pxbzqk3ZlS3qOuh5S38I=";
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
  version = "19";

  src = fetchFromGitHub {
    owner = "official-stockfish";
    repo = "Stockfish";
    rev = "sf_${version}";
    hash = "sha256-4sRJb8zYhbkuIsI6pOcfH6ZIotXBp7k1kHlxL8jk3vQ=";
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

  evalFile = net;
  evalFileName = netFile;

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
    description = "Stockfish 19, the strongest open-source UCI chess engine, NNUE-based";
    homepage = "https://stockfishchess.org/";
    # Copying.txt is the verbatim GPLv3 text; every source header (e.g.
    # src/types.h) reads "version 3 of the License, or (at your option) any
    # later version", i.e. GPL-3.0-or-later. The net in
    # official-stockfish/networks is distributed under the same GPLv3.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
