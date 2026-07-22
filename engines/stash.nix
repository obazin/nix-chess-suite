{ lib, mkEngine, fetchFromGitHub }:

mkEngine rec {
  pname = "stash";
  version = "37.0";

  src = fetchFromGitHub {
    owner = "mhouppin";
    repo = "stash-bot";
    rev = "v${version}";
    hash = "sha256-HZKNQw9JIELbw2ofCqzeNKxTQGow7ZgHVGjb+bgB610=";
  };

  sourceRoot = "source/src";

  # Stash has a real arch-detection path, so mkEngine's blanket sed would only
  # corrupt it. ARCH=generic short-circuits detection entirely and emits no
  # x86 codegen flags, which is exactly what we want on aarch64 and what keeps
  # the x86_64 build reproducible across host CPUs.
  stripArchFlags = false;
  makeFlags = [ "ARCH=generic" ];

  postPatch = ''
    # -Werror against a compiler the author did not test turns any new
    # diagnostic into a build failure.
    substituteInPlace Makefile --replace-fail 'CPPFLAGS ?= -Werror' 'CPPFLAGS ?='
  '';

  meta = with lib; {
    description = "Stash, a UCI chess engine written from scratch in C by Morgan Houppin";
    homepage = "https://github.com/mhouppin/stash-bot";
    # LICENSE is the GPLv3 text; src/Makefile and every source header carry the
    # "either version 3 ... or (at your option) any later version" notice.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
