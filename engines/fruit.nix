{ lib, mkEngine, fetchFromGitHub }:

mkEngine rec {
  pname = "fruit";
  version = "2.1";

  # Fruit 2.1 is the last GPL release. 2.2-2.3.1 are proprietary, and 2.3+
  # was transferred to a different maintainer under non-GPL terms, so this
  # tag must never be bumped.
  src = fetchFromGitHub {
    owner = "Warpten";
    repo = "Fruit-2.1";
    rev = "09627df3835f205c92ece013219c7a99ac4a023a";
    hash = "sha256-zTvN/fy+uDGu7TY8YL6HPz1BcHbLKddpz4xftRdEmTc=";
  };

  sourceRoot = "source/src";

  # The default `all` target also builds .depend via makedepend, which we
  # neither have nor need.
  makeTarget = "fruit";

  binaries = [ "fruit" ];

  postPatch = ''
    # `ld -s` is obsolete on Darwin and errors on recent cctools.
    substituteInPlace Makefile --replace-fail 'LDFLAGS += -s' '# LDFLAGS += -s'
  '';

  meta = with lib; {
    description = "Fruit 2.1, Fabien Letouzey's influential UCI engine and the ancestor of Toga II";
    homepage = "https://www.chessprogramming.org/Fruit";
    # copying.txt in the release is GPLv2-or-later, NOT v3.
    license = licenses.gpl2Plus;
    maintainers = [ ];
  };
}
