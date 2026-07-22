{ lib, stdenv, mkEngine, fetchurl, cmake }:

mkEngine rec {
  pname = "jazz";
  version = "8.40";

  # Evert Glebbeek distributes Jazz only as source tarballs from his own site
  # (there is no upstream git repo), so pin the URL + hash directly. His
  # download page states: "Both Jazz and Sjaak are distributed under the terms
  # of the GNU General Public Licence", linking GPL-3.0, and the tarball's
  # COPYING file is the GPLv3 text.
  #
  # The URL path uses "jazz-840" (lowercase) but the tarball unpacks to a
  # capitalised "Jazz/" directory, hence sourceRoot below.
  src = fetchurl {
    url = "http://www.eglebbk.dds.nl/program/download/jazz-840-src.tar.gz";
    sha256 = "1hjrncy017rgz3ka02s9icwp45b1d4asyflc5v7q249ihpw66vmz";
  };

  sourceRoot = "Jazz";

  nativeBuildInputs = [ cmake ];

  # Which binary actually speaks UCI is a subtle point. Jazz ships a standalone
  # UCI interface source (src/interface/uci.c -> the `ucijazz` target, gated by
  # WANT_UCI), but in 8.40 that file is abandoned: it still calls the removed
  # `computer_play()` and reads gamestate_t fields (movestogo, time_left,
  # time_inc) that have since moved into a separate chess_clock_t. It does not
  # compile against this version's library, which is why WANT_UCI defaults OFF.
  #
  # The maintained interface is `xbjazz` (src/interface/xboard.c), and despite
  # the name it implements BOTH protocols: sending `uci` puts it in UCI mode and
  # it answers `id name Jazz ...` / `uciok`. So xbjazz IS the UCI engine here;
  # we build it (WANT_XBOARD is ON by default) and install it as `jazz`, leaving
  # the dead ucijazz target switched off.
  #
  # There is no Makefile for mkEngine's stripArchFlags to rewrite, so x86 codegen
  # is controlled through CMake options:
  #   WANT_SSE42  default ON  -- adds -msse4.2, fatal on aarch64. Turn OFF.
  #   WANT_READLINE default ON -- turned OFF so we need no readline input; xbjazz
  #               builds fine without it (HAVE_READLINE just stays unset).
  #   WANT_NATIVE default OFF -- good, keeps -march=native out.
  #   WANT_SMP    default ON  -- fine, just adds -pthread.
  cmakeFlags = [
    # The tree declares cmake_minimum_required(2.4), which CMake >= 4 refuses
    # outright. This flag tells CMake to run the old policy set anyway.
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    "-DWANT_SSE42=OFF"
    "-DWANT_READLINE=OFF"
    "-DWANT_LTO=OFF" # LTO across this old GNU C tree is slow and buys nothing here
  ];

  # CMake builds land in the build dir. Install xbjazz as bin/xbjazz, symlinked
  # to bin/jazz (what the smoke test invokes).
  binaries = [ "xbjazz" ];

  meta = with lib; {
    description = "Jazz 8.40, Evert Glebbeek's UCI chess engine";
    homepage = "http://www.eglebbk.dds.nl/program/chess-index.html";
    # COPYING is GPLv3; README says "Jazz is distributed under the GPL" and the
    # author's site states GPL-3.0 explicitly. No "or later" wording, so gpl3Only.
    license = licenses.gpl3Only;
    maintainers = [ ];
  };
}
