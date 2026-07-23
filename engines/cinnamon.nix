{ lib, stdenv, mkEngine, fetchFromGitHub }:

mkEngine rec {
  pname = "cinnamon";
  # constants.h still reads `NAME = "Cinnamon 2.5"` at this commit, so 2.5 is
  # what the engine calls itself over UCI.
  version = "2.5";

  # Pinned to master rather than the v2.5 tag on purpose. At v2.5 the
  # committed src/Makefile is a *CMake-generated* one carrying the author's
  # absolute paths (/home/geko/workspace/..., /usr/bin/cmake) and is
  # unbuildable anywhere but his machine. master restores the hand-written
  # cross-compile Makefile with the real cinnamon64-* targets. Nothing
  # affecting play changed between the two.
  src = fetchFromGitHub {
    owner = "gekomad";
    repo = "Cinnamon";
    rev = "09a91c5d179760fa342ca873d4ef014c30a33526";
    hash = "sha256-xXZZZRg16ELjqPfT/olUxIvJ9qCnypVsoCzt75wiQtw=";
  };

  sourceRoot = "source/src";

  # The Makefile is a menu of CPU-specific targets rather than one portable
  # build. cinnamon64-modern* all inject -msse3/-mpopcnt/-march=corei7;
  # cinnamon64-ARM injects only the -DHAS_POPCNT/-DHAS_BSF feature defines,
  # which map onto compiler builtins and are correct everywhere. Pick by host
  # so aarch64 gets the ARM path and x86_64 gets the plain 64-bit path.
  #
  # mkEngine's stripArchFlags also scrubs the x86 flags out of the Makefile,
  # which is belt-and-braces here but matters if the target ever changes.
  makeTarget =
    if stdenv.hostPlatform.isAarch then "cinnamon64-ARM" else "cinnamon64-generic";

  binaries = [ "cinnamon" ];

  # The Makefile hardcodes COMP=g++ and never consults $CXX, so the CC=/CXX=
  # that mkEngine passes are ignored. COMP given on the command line does
  # propagate to the recursive $(MAKE) invocations the targets use.
  makeFlags = [ "COMP=${stdenv.cc.targetPrefix}c++" ];

  postPatch = ''
    # The Gaviota tablebase prober is vendored under db/gaviota and compiled
    # into the binary unconditionally; there is no external libgtb.a to link
    # and no tablebase files are installed, so the engine runs with tablebase
    # support inert. Project policy is no tablebases - they buy nothing at
    # this strength - so nothing is added here to enable them.

    # `strip` on the freshly built binary breaks the Nix fixup phase's own
    # stripping on Darwin and gains us nothing (fixupPhase strips anyway).
    substituteInPlace Makefile --replace-fail '$(STRIP) $(EXE)' 'true'

    # The Makefile links with a bare `-lpthread`, which the GNU linker in the
    # Linux sandbox cannot resolve (glibc folds pthread into libc). `-pthread`
    # lets the compiler driver handle threading correctly on both platforms.
    sed -i 's/-lpthread/-pthread/g' Makefile

    # The ARM/generic link targets pass `-static` / `-static-libgcc` /
    # `-static-libstdc++`. Full static linking needs static libm/libc, which
    # nixpkgs' default glibc does not ship ("cannot find -lm"). Drop the static
    # flags on Linux; a normal dynamic link is what Nix expects anyway.
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      sed -i -e 's/-static-libstdc++//g' -e 's/-static-libgcc//g' \
             -e 's/ -static / /g' -e 's/ -static$/ /g' Makefile
    ''}
  '';

  meta = with lib; {
    # Gated off Windows: its vendored syzygy/gaviota build chain fails under
    # the mingw cross (a build tool returns 127).
    platforms = platforms.unix;
    description = "Cinnamon, Giuseppe Cannella's UCI engine with Chess960 and multithreaded perft";
    homepage = "https://github.com/gekomad/Cinnamon";
    # LICENCE DISCREPANCY, resolved conservatively as GPLv3-or-later:
    #   * every source header, including src/main.cpp and src/Makefile, carries
    #     the GPL notice "either version 3 of the License, or (at your option)
    #     any later version";
    #   * README.md says "GPL 3 License" and "Cinnamon is released under the
    #     GPLv3+ license";
    #   * but the repository LICENSE file contains the text of the GNU *Lesser*
    #     GPL 3.0, not the GPL.
    # The headers govern the code itself and are the stricter reading, so
    # gpl3Plus is what we record. See docs/excluded.md ("Unresolved").
    # https://github.com/gekomad/Cinnamon/blob/master/src/main.cpp
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
