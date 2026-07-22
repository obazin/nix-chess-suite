{ lib, stdenv, mkEngine, fetchzip }:

mkEngine rec {
  pname = "ct800";
  version = "1.46";

  # CT800 has no public VCS; the author distributes versioned release zips
  # from ct800.net, which is the only primary source.
  src = fetchzip {
    url = "https://www.ct800.net/downloads/ct800-v${version}.zip";
    hash = "sha256-jGrrKW23Sj3WD+ltQMU+9rOqpOgsgny9dtjbg31vSYE=";
  };

  # CT800 is primarily firmware for a dedicated STM32 chess computer; that
  # target lives in source/application and needs an arm-none-eabi toolchain
  # and a linker script. source/application-uci is the portable PC port,
  # which is what we want.
  sourceRoot = "source/source/application-uci";

  # Upstream ships one shell script per platform instead of a Makefile. We
  # follow make_ct800_mac.sh / make_ct800_linux.sh, minus their -Werror
  # (a new compiler diagnostic should not be a build failure), minus
  # -march=native/-mtune=native (not reproducible, and meaningless here), and
  # minus the -m64 that would break aarch64.
  #
  # NO_MONO_COND drops the pthread_condattr_setclock(CLOCK_MONOTONIC) path,
  # which Darwin does not implement.
  buildPhase = ''
    runHook preBuild
    $CC -pthread -O3 -std=c99 \
      -fno-strict-aliasing -fno-strict-overflow -fno-common \
      ${lib.optionalString stdenv.hostPlatform.isDarwin "-DNO_MONO_COND"} \
      play.c tuner.c kpk.c eval.c move_gen.c hashtables.c search.c util.c \
      book.c kpk_table.c bookdata.c \
      -o ct800 ${lib.optionalString stdenv.hostPlatform.isLinux "-lrt"}
    runHook postBuild
  '';

  meta = with lib; {
    description = "CT800, Rasmus Althoff's UCI port of the CT800 dedicated chess computer firmware";
    homepage = "https://www.ct800.net/";
    # COPYING.txt in the release is the GPLv3 text; readme.txt states "version
    # 3 or any later version", and every source file carries an
    # SPDX-License-Identifier: GPL-3.0-or-later header.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
