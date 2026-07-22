{ lib, stdenv, mkEngine, fetchzip }:

mkEngine rec {
  pname = "cheng4";
  version = "4.48";

  # kmar/cheng4_releases is a release-only repository: the git tree holds
  # nothing but a README, and the source lives inside the release zip
  # alongside the author's prebuilt binaries. We take the zip and build from
  # its src/ tree rather than shipping cheng4_osx_arm64.
  src = fetchzip {
    url = "https://github.com/kmar/cheng4_releases/releases/download/${version}/cheng4_48.zip";
    hash = "sha256-RlG5eWwAyyYCzC4c7VAk1MPdImqQkXOR9zu6U3YTkj8=";
  };

  sourceRoot = "source/src/cheng4";

  # No Makefile at all — upstream ships one shell one-liner per platform. They
  # all compile allinone.cpp, a unity build that #includes every other .cpp,
  # so a single compiler invocation is the whole build. The NNUE is embedded
  # in nets/net_embed.h, so nothing is fetched at build time.
  buildPhase = ''
    runHook preBuild
    $CXX -O3 -std=c++14 -DNDEBUG -fno-rtti -fno-exceptions \
      allinone.cpp -o cheng4 -lpthread
    runHook postBuild
  '';

  # Engine::init opens "cheng2024.cb" relative to the working directory, so
  # the book is only picked up if the user cds next to it; install it anyway
  # so it is not lost.
  dataFiles = [ "../../cheng2024.cb" ];

  meta = with lib; {
    description = "Cheng 4, Martin Sedlak's NNUE engine, built from the release source rather than the shipped binary";
    homepage = "https://github.com/kmar/cheng4_releases";
    # Every source file, e.g. src/cheng4/main.cpp, carries verbatim zlib
    # licence text: "either the following zlib-compatible license or as public
    # domain". The bundled Syzygy prober (src/cheng4/pyrrhic) is MIT.
    license = with licenses; [ zlib mit ];
    maintainers = [ ];
  };
}
