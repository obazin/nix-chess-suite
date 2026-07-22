{ lib, mkEngine, fetchFromGitHub }:

mkEngine rec {
  pname = "shallow-blue";
  version = "2.0.0";

  # v2.0.0 is the last release; upstream has been dormant since 2019. The tag
  # and the current master head are the same commit, so pinning the tag costs
  # nothing.
  src = fetchFromGitHub {
    owner = "GunshipPenguin";
    repo = "shallow-blue";
    rev = "a04fbd9861770c897eb566d83b0d2e3b17aa9fc0";
    hash = "sha256-PgAwByWzDe5Blll62aLhiodvcpKKWwoodDiZc+HbD3U=";
  };

  # `all` is the default target and builds only the engine. The `test` target
  # would pull in Catch and is not what we want in the sandbox.
  makeTarget = "all";

  # BIN_NAME in the Makefile; mkEngine symlinks bin/shallow-blue onto it.
  binaries = [ "shallowblue" ];

  # CC_FLAGS carries -march=native, which mkEngine's stripArchFlags removes.
  # Both CC_FLAGS and LD_FLAGS also carry a bare -flto, which stripArchFlags
  # does *not* match (it only matches -flto=<mode>). Plain -flto is fine for
  # clang on aarch64-darwin, so it is left alone.
  postPatch = ''
    # The Makefile does `mkdir obj` unconditionally via the $(OBJ_DIR) rule,
    # which fails if a stale dir exists. Make it idempotent.
    substituteInPlace Makefile --replace-fail 'mkdir $(OBJ_DIR)' 'mkdir -p $(OBJ_DIR)'

    # option.h uses std::string with only <map> included; gcc/libstdc++ (linux)
    # does not pull <string> in transitively the way clang/libc++ (darwin) does.
    substituteInPlace src/option.h \
      --replace-fail '#include <map>' '#include <map>
#include <string>
#include <cstdint>'
  '';

  meta = with lib; {
    description = "Shallow Blue, a small didactic UCI engine by Rhys Rustad-Elliott (~1900 Elo)";
    homepage = "https://github.com/GunshipPenguin/shallow-blue";
    # Verified against the upstream LICENSE file: verbatim MIT text,
    # "Copyright (c) 2017-2019 Rhys Rustad-Elliott".
    # https://github.com/GunshipPenguin/shallow-blue/blob/master/LICENSE
    license = licenses.mit;
    maintainers = [ ];
  };
}
