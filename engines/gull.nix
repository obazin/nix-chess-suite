{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub }:

# IMPORTANT PLATFORM CAVEAT
# Gull is x86_64-only and this file is NOT build-verified. Vadim Demichev's
# engine is written directly against x86 hardware: src/Gull.cpp uses inline
# x86-64 assembly (`bsfq`/`bsrq`), `_mm_popcnt_u64` via <popcntintrin.h>, and
# `_mm_prefetch`, with no NEON or scalar fallback. Its Makefile.linux is
# equally x86/GNU-specific: it forces -msse4.1 -mpopcnt and links with -lrt and
# a set of `-Wl,--defsym=SYMBOL=0xADDRESS` flags that place shared-memory
# regions at fixed virtual addresses via GNU ld. None of this survives on
# aarch64 or on the macOS linker, so the engine cannot be built on this repo's
# only Nix host (aarch64-darwin). meta.platforms is therefore restricted to
# x86_64-linux/-windows, which makes the flake skip it here, exactly as
# obsidian.nix does. The Fathom pinning below is verified (the fetch resolves);
# the compile/link wiring is best-effort and must be checked on an x86_64-linux
# runner before this engine is relied upon.

let
  # basil00's Linux/Mac port of Gull downloads Fathom (the Syzygy prober) with
  # `wget` from its `tb` Makefile target, which the sandbox forbids. Pin the
  # exact Fathom the port targets and drop it in instead (see postPatch). Its
  # src/ holds tbprobe.{c,h} and tbcore.{c,h}, the four files the `tb` target
  # unzips.
  fathom = fetchFromGitHub {
    owner = "basil00";
    repo = "Fathom";
    rev = "611b29583ea358cb3e5322ce6c598d79e296f8db";
    hash = "sha256-MGV4Bqbyp4u81e8gzyv4CFOfWRasaGwgRlS6MwzFTCg=";
  };
in
mkEngine rec {
  pname = "gull";
  version = "3-2019";

  # Gull 3 was released into the PUBLIC DOMAIN by Vadim Demichev. basil00/Gull
  # is the maintained Linux/Mac port ("LazyGull"); its LICENSE restates the
  # original as public domain and licenses the port's own modifications under
  # MIT. Untagged, so pinned by commit.
  src = fetchFromGitHub {
    owner = "basil00";
    repo = "Gull";
    rev = "6d956f9d85ba90f90d4d72d486f577c8dfa89c88";
    hash = "sha256-/1jC5ca5W2DrM5GHsNMIHz5/NLgE/EmnoZfnNpc1Vco=";
  };

  sourceRoot = "source/src";

  # Gull's makefiles hardcode the required x86 codegen (-msse4.1 -mpopcnt); the
  # engine cannot run without them, so mkEngine's arch-flag strip must stay off.
  stripArchFlags = false;

  # Upstream ships no plain `Makefile`; select Makefile.linux explicitly and its
  # `build` target. `pgo-build` runs the freshly built binary mid-build, so it
  # is avoided.
  makeFlags = [ "-f" "Makefile.linux" ];
  makeTarget = "build";
  binaries = [ "LazyGull" ];

  postPatch = ''
    # Supply Fathom from the pinned source and stop `build` depending on the
    # `tb` target, which would otherwise wget it at build time.
    cp ${fathom}/src/tbprobe.h ${fathom}/src/tbprobe.c \
       ${fathom}/src/tbcore.h ${fathom}/src/tbcore.c .
    substituteInPlace Makefile.linux --replace-fail 'build: tb' 'build:'

    # The recipes compile the C++ Gull.cpp with $(CC); mkEngine sets CC to the C
    # driver, which would link without the C++ runtime. Route them through
    # $(CXX) (which mkEngine sets to the C++ driver) instead.
    substituteInPlace Makefile.linux --replace '$(CC) $(CFLAGS)' '$(CXX) $(CFLAGS)'
  '';

  meta = with lib; {
    description = "Gull 3 (basil00's LazyGull port), Vadim Demichev's public-domain engine (x86_64 only, unverified)";
    homepage = "https://github.com/basil00/Gull";
    # LICENSE: "The original Gull chess source code is public domain. New
    # modifications are released under the MIT License." Hence public domain for
    # the engine core, MIT for the port's changes.
    license = with licenses; [ publicDomain mit ];
    # x86_64-only: no ARM/scalar path, plus Linux-specific fixed-address linking.
    # See the header comment. Not build-verified on any host available here.
    platforms = [ "x86_64-linux" "x86_64-windows" ];
    maintainers = [ ];
  };
}
