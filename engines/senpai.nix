{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub }:

mkEngine rec {
  pname = "senpai";
  version = "2.0";

  # Senpai is Fabien Letouzey's SECOND engine, unrelated to Fruit. He released
  # 2.0 as a bare source archive rather than through a repository, so we pin a
  # faithful mirror. MichaelB7/Senpai carries his verbatim GPLv3 licence.txt and
  # the unmodified src/ tree (src/main.cpp still reports Engine_Version "2.0").
  # 2.0 is the classical-eval release: there is NO NNUE net, which is exactly
  # why it is preferred here — nothing to fetch or pin. The mirror is untagged,
  # so it is pinned by commit.
  src = fetchFromGitHub {
    owner = "MichaelB7";
    repo = "Senpai";
    rev = "2aea5f4096e33eef1ee943b4c0b9c0de244d9331";
    hash = "sha256-vxZC53CQlAUGJ6Q5RZTiEkVUtgigq2I5ou4YTOSxE5U=";
  };

  sourceRoot = "source/src";

  # Default target is `all` -> senpai. The Makefile hardcodes CXX = clang++ and
  # -march=native; mkEngine's CXX= makeflag overrides the former and its
  # arch-flag strip removes the latter, leaving a portable -O3 -flto build.
  binaries = [ "senpai" ];

  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"
    # Classical eval, but still assert a real search returns a bestmove: this
    # catches a binary that answers the handshake yet dies once told to think.
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
    description = "Senpai 2.0, Fabien Letouzey's classical (non-NNUE) UCI chess engine";
    homepage = "https://www.chessprogramming.org/Senpai";
    # licence.txt is the verbatim GPLv3 text; the README states "This program is
    # distributed under the GNU General Public License version 3." with no "or
    # later" clause, so the conservative reading is GPL-3.0-only.
    license = licenses.gpl3Only;
    maintainers = [ ];
  };
}
