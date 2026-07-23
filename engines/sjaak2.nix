{ lib, stdenv, mkEngine, fetchurl, cmake }:

mkEngine rec {
  pname = "sjaak2";
  version = "1.4.1";

  # Sjaak II, Evert Glebbeek's variant-capable engine, younger sibling of Jazz.
  # Same author, same distribution model (source tarball from his own site, no
  # git repo), same licence: his download page states "Both Jazz and Sjaak are
  # distributed under the terms of the GNU General Public Licence" (GPL-3.0),
  # and the tarball's COPYING is the GPLv3 text.
  #
  # PROTOCOL CHECK (this is a UCI-only collection): despite the file being named
  # xboard.cc, Sjaak II's single binary implements UCI natively. Sending `uci`
  # sets it to UCI mode and it replies `id name Sjaak ...` / `uciok` (it also
  # speaks the ucci and usi dialects, and advertises UCI_Variant / UCI_Chess960).
  # The smoke test's plain `uci` handshake exercises exactly this path in
  # standard-chess mode, so it is a genuine UCI engine and is in scope.
  src = fetchurl {
    url = "http://www.eglebbk.dds.nl/program/download/sjaakii-1.4.1-src.tar.gz";
    sha256 = "1lcjwkfk39pfm96xrygmkwc7pi0i5djypa1r7pl9zl9i7xmygm5c";
  };

  sourceRoot = "SjaakII";

  nativeBuildInputs = [ cmake ];

  postPatch = ''
    # The sjaakii target has a POST_BUILD custom command that runs `pod2man`
    # (Perl) to build a man page we don't install. Drop it so the build needs
    # no Perl in the sandbox.
    substituteInPlace CMakeLists.txt \
      --replace-fail 'COMMAND pod2man -s 6 ''${CMAKE_SOURCE_DIR}/sjaakii.pod | gzip > ''${CMAKE_BINARY_DIR}/sjaakii.6.gz' \
                     'COMMAND true'
  '';

  # CMake project, no Makefile for stripArchFlags to touch, so x86 codegen is
  # controlled via options:
  #   WANT_SSE42  default ON  -- adds -msse4.2, fatal on aarch64. Turn OFF.
  #   WANT_POPCNT default OFF -- good, no popcnt intrinsic on aarch64.
  #   WANT_NATIVE default OFF -- good.
  #   WANT_REFEREE default ON -- builds the `sjef` tool, which uses Linux-only
  #               pipe2() and would fail to compile on Darwin. We don't need it,
  #               so turn it OFF.
  # readline is picked up opportunistically by find_package (no REQUIRED); with
  # no readline input it just prints a warning and builds without line editing.
  cmakeFlags = [
    # cmake_minimum_required(2.8.12) is rejected by CMake >= 4; run old policies.
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    "-DWANT_SSE42=OFF"
    "-DWANT_REFEREE=OFF"
  ];

  # Single target `sjaakii`; installed as bin/sjaakii and symlinked to bin/sjaak2
  # (what the smoke test invokes).
  binaries = [ "sjaakii" ];

  meta = with lib; {
    # Gated off Windows: CMake project does not configure for the mingw cross.
    platforms = platforms.unix;
    description = "Sjaak II 1.4.1, Evert Glebbeek's variant-capable UCI/XBoard engine";
    homepage = "http://www.eglebbk.dds.nl/program/chess-index.html";
    # COPYING is GPLv3; author's site states GPL-3.0 with no "or later" wording.
    license = licenses.gpl3Only;
    maintainers = [ ];
  };
}
