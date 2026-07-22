{ lib, stdenv, mkEngine, fetchurl, p7zip }:

mkEngine rec {
  pname = "deeptoga";
  version = "1.9.6-nps";

  # DeepToga's own sites are gone. Lucas Chess is the only surviving
  # distributor of the source, and it ships two different trees: this one,
  # under bin/OS/linux, and "src for DeepToga1.9.6changed.7z" under bin/OS/win32.
  # Only the Linux tree guards its <windows.h> includes behind _WIN32/_WIN64,
  # so it is the one that can be built here. Pinned to a commit rather than a
  # branch because the path is a raw blob, not a release artifact.
  src = fetchurl {
    url = "https://raw.githubusercontent.com/lukasmonk/lucaschessR2/b3ab7678077d6433e45d85f55acac2102e13e82e/bin/OS/linux/Engines/toga/src.7z";
    hash = "sha256-OWyU41tIk6RCwL405ibPci7LIK9rJx+S/Cj+KW5IH4k=";
  };

  nativeBuildInputs = [ p7zip ];

  # Overridden wholesale because stdenv cannot unpack .7z, which also means
  # the usual `cd $sourceRoot` never happens and has to be done by hand.
  unpackPhase = ''
    runHook preUnpack
    7z x "$src"
    cd src
    runHook postUnpack
  '';

  # `all` also generates .depend; the binary target alone is enough.
  makeTarget = "deeptoga";

  binaries = [ "deeptoga" ];

  postPatch = ''
    substituteInPlace Makefile \
      --replace-fail 'EXE = DeepToga1.9.6nps' 'EXE = deeptoga'
  ''
  # dlopen/dlsym live in libSystem on Darwin; there is no libdl to link.
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    substituteInPlace Makefile --replace-fail '-ldl -lpthread' '-lpthread'
  ''
  + ''
    # Ordered comparison of a FILE* against NULL. GCC 4 accepted it; clang
    # rejects it outright, and the intent is plainly an inequality test.
    substituteInPlace protocol.cpp \
      --replace-fail 'fp_debug > NULL' 'fp_debug != NULL'

    # my_sem_t and its three helpers are gated on __linux__, but the
    # implementation is a plain pthread mutex + condvar with nothing
    # Linux-specific in it. Without widening the guard, search.cpp's thread
    # code fails to compile on Darwin.
    substituteInPlace util.h util.cpp \
      --replace-fail '#if defined(__linux__)' \
                     '#if defined(__linux__) || defined(__APPLE__)'
  '';

  meta = with lib; {
    description = "DeepToga 1.9.6 NPS, a multi-threaded Toga II derivative with node-rate throttling";
    homepage = "https://www.chessprogramming.org/Toga";
    # The distribution ships COPYING (GPLv2 text) and LICENSE, the latter
    # quoting Gaksch's Toga II 1.4beta5c notice from superchessengine.com:
    # "based on Fruit 2.1 by Fabien Letouzey ... either version 2 of the
    # License, or (at your option) any later version".
    # https://github.com/lukasmonk/lucaschessR2/blob/main/bin/OS/linux/Engines/toga/LICENSE
    license = licenses.gpl2Plus;
    maintainers = [ ];
  };
}
