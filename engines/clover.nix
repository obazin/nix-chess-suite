{ lib, mkEngine, fetchFromGitHub }:

mkEngine rec {
  pname = "clover";
  version = "9.1";

  src = fetchFromGitHub {
    owner = "lucametehau";
    repo = "CloverEngine";
    rev = "v${version}";
    hash = "sha256-sYE0RQpslRCV11eNdu+wCFTUXRhJHXSRKekqMHvqGCg=";
  };

  sourceRoot = "source/src";

  # Unlike every other NNUE engine here, Clover commits its quantised net
  # (src/quantised.nnue) straight into the repo. The Makefile embeds it via
  # INCBIN (net.h: `INCBIN(Net, EVALFILE)`, EVALFILE=quantised.nnue), so the
  # build fetches nothing from the network and needs no pinned fetchurl.

  # The Makefile's real target is literally named `make`; the default goal is
  # a `native`-flavoured build. build_flag=generic is an intentional no-op:
  # none of the arch branches (old/avx2/avx512/native/tune/generate) match it,
  # so BUILD_FLAGS keeps only the EVALFILE/PEXT/version defines and gains no
  # -march / -mno-avx512f codegen flags. That is exactly what we want on
  # aarch64, where the default `native` path (`-mno-avx512f -march=native`)
  # would be nonsensical.
  makeTarget = "make";
  makeFlags = [ "build_flag=generic" ];

  # EXE = Clover.$(VERSION); no arch suffix is appended for build_flag=generic.
  binaries = [ "Clover.${version}" ];

  postPatch = ''
    # -flto-partition=one is a GCC-only option; clang errors on it outright.
    # Plain -flto (kept) is fine with the Darwin toolchain. The x86 -march
    # flags are already handled by mkEngine's stripArchFlags sed.
    substituteInPlace makefile --replace-fail ' -flto-partition=one' ""

    # Bitboard has an implicit `operator unsigned long long()` *and* its own
    # operator== / operator!=. Under C++20's rewritten-comparison-candidate
    # rules clang rejects `someBitboard != 0` as ambiguous (built-in
    # ull-comparison via the conversion vs. the member operators); GCC, which
    # upstream builds with, quietly accepts it. Dropping the three redundant
    # member comparison operators makes every comparison go through the
    # implicit ull conversion to the built-in operators — same semantics, no
    # ambiguity — so the code builds identically under both compilers.
    substituteInPlace bitboard.h \
      --replace-fail '    constexpr bool operator!=(const Bitboard &other) const
    {
        return bb != other.bb;
    }
' "" \
      --replace-fail '    constexpr bool operator!=(const unsigned long long &other) const
    {
        return bb != other;
    }
' "" \
      --replace-fail '    constexpr bool operator==(const Bitboard &other) const
    {
        return bb == other.bb;
    }
' ""
  '';

  meta = with lib; {
    description = "Clover, Luca Metehau's NNUE UCI engine, with its quantised net committed in-repo";
    homepage = "https://github.com/lucametehau/CloverEngine";
    # LICENSE is the GPLv3 text; src/main.cpp and src/uci.h headers carry the
    # "either version 3 ... or (at your option) any later version" notice.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
