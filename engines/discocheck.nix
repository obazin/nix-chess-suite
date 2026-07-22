{ lib, mkEngine, fetchFromGitHub }:

mkEngine rec {
  pname = "discocheck";
  version = "5.2";

  # Lucas Braesch's DiscoCheck. His own repo (lucasart/chess) is gone -- he
  # deleted it after moving on to Demolito -- so pin phenri/chess, a plain
  # (non-fork) mirror that carries the full history, the GPL `license` file and
  # the version tags. v5.2 is the last DiscoCheck release; `id name` reports
  # "DiscoCheck 5.2" from this commit.
  src = fetchFromGitHub {
    owner = "phenri";
    repo = "chess";
    rev = "3607740cd921a2f258ca4b0000c5b35794ff6f53"; # tag v5.2
    hash = "sha256-iCies4pXM6QosZSdVgqpCTxGY3hFH9+76eoY9zYuENE=";
  };

  # make.sh is `g++ ./src/*.cc -o $1 ... -msse4.2 -flto -s`. mkEngine's
  # stripArchFlags removes -msse4.2 (and the -flto=<jobs> pattern, though plain
  # -flto here is untouched and harmless). The build itself is one command;
  # rather than fight make.sh's `$1` output-name convention, invoke g++ directly.
  buildPhase = ''
    runHook preBuild
    $CXX ./src/*.cc -o ${pname} -std=c++11 -DNDEBUG -O3 -fno-rtti -flto
    runHook postBuild
  '';

  binaries = [ "discocheck" ];

  meta = with lib; {
    description = "DiscoCheck 5.2, Lucas Braesch's compact UCI engine (predecessor of Demolito)";
    homepage = "https://www.chessprogramming.org/DiscoCheck";
    # Every source file carries the GPLv3-or-later header ("either version 3 of
    # the License, or (at your option) any later version"); the `license` file
    # is the GPLv3 text and README's "Terms of use" restates the GPL.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
