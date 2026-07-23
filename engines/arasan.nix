{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub, bc, gawk, git, which, clang }:

let
  # src/syzygy is a git submodule (jdart1/Fathom) that the release tarball does
  # not carry, but Syzygy support is NOT cleanly optional: protocol.cpp
  # references SearchOptions::syzygy_* members that only exist under
  # -DSYZYGY_TBS, so the feature cannot simply be switched off. Vendor Fathom
  # into src/syzygy/src (where STB=syzygy/src expects tbprobe.c) instead. Pinned
  # to the submodule commit recorded in arasan v25.4.
  fathom = fetchFromGitHub {
    owner = "jdart1";
    repo = "Fathom";
    rev = "c9c6fef0dddc05d2e242c183acf5833149ab676d";
    hash = "sha256-P3YjOTjFlOqHUukk7FiG1fs18T89DWtpMQ1hwFAjebw=";
  };
in
mkEngine rec {
  pname = "arasan";
  version = "25.4";

  # Jon Dart's own 30-year codebase. Relicensed to MIT at v14; current releases
  # are NNUE. The net is committed in-repo (network/arasanv5-20251222.nnue,
  # ~24 MB) and read at runtime, so nothing is fetched at build time.
  src = fetchFromGitHub {
    owner = "jdart1";
    repo = "arasan-chess";
    rev = "v${version}";
    hash = "sha256-o1Hjt6GhgCI12uOlRyctnSzMDWphTXDAXEjNwp23iHw=";
  };

  sourceRoot = "source/src";

  # bc + gawk are invoked only on the GCC code path (Linux) to gate the compiler
  # version; the Darwin build takes the clang branch and needs neither. Harmless
  # to always provide, and keeps the x86_64-linux build honest.
  # git + which: the Makefile shells out to both to derive a version string.
  # They happen to be on PATH on the macOS runner but not in the Linux sandbox.
  # clang (aarch64-linux only): Arasan's NEON SIMD returns a uint8x16_t where an
  # int8x16_t is expected; clang accepts the vector-signedness mismatch, gcc
  # rejects it. Darwin already uses clang; x86_64-linux uses the SSE path (no
  # NEON), so only the aarch64-linux/gcc combination needs it.
  nativeBuildInputs = [ bc gawk git which ]
    ++ lib.optional (stdenv.hostPlatform.isAarch64 && stdenv.hostPlatform.isLinux) clang;

  # Arasan has real per-arch BUILD_TYPEs, so mkEngine's blanket flag-strip would
  # only corrupt its x86 branches. On aarch64 the "neon" type emits -DSIMD
  # -DNEON and NO arch codegen flags at all (NEON is baseline on ARMv8), which
  # is exactly the portable build we want; on x86_64 "modern" is the popcnt/SSE
  # baseline. PGO targets ("make profiled") are avoided on purpose: they run the
  # just-built binary mid-build, which the sandbox forbids.
  stripArchFlags = false;
  # BUILD_TYPE picks the arch. LBITS is normally `getconf LONG_BIT`, but getconf
  # is absent from the build sandbox and returns empty, which drops -D_64BIT and
  # names the binary `arasanx--neon`; pin it to 64. The Makefile's link recipe
  # does `cd ../build && ld ../build/*.o`, a trick that only resolves with the
  # default ../-prefixed output dirs, so those are left untouched (see preBuild).
  makeFlags = [
    (if stdenv.hostPlatform.isAarch64 then "BUILD_TYPE=neon" else "BUILD_TYPE=modern")
    "LBITS=64"
  ];

  postPatch = ''
    # Arasan's POSIX includes are guarded only by !defined(_MSC_VER); mingw is
    # Windows but not MSVC, so it wrongly pulls in <sys/resource.h> et al. Also
    # exclude _WIN32 so mingw takes the _WIN32 branch below.
    substituteInPlace globals.cpp \
      --replace-quiet '#elif !defined(_MSC_VER)' '#elif !defined(_MSC_VER) && !defined(_WIN32)'

    # types.h puts the Windows aligned-alloc (_aligned_malloc from <malloc.h>)
    # under `#ifdef _MSC_VER`, so mingw falls through to std::aligned_alloc,
    # which mingw's libstdc++ (UCRT, no C11 aligned_alloc) lacks. mingw HAS
    # _aligned_malloc, so let it into that block too.
    substituteInPlace types.h \
      --replace-quiet '#ifdef _MSC_VER
extern "C" {
   #include <malloc.h>' '#if defined(_MSC_VER) || defined(__MINGW32__)
extern "C" {
   #include <malloc.h>'

    # The x86 build types add -fuse-ld=gold; the gold linker isn't in the mingw
    # cross toolchain, so collect2 fails with "cannot find 'ld'". Default bfd
    # links fine. (Windows only, to keep gold on Linux where it's present.)
    #
    # LIBS starts as `-lc -lm`. mingw has no standalone libc (the CRT — msvcrt/
    # ucrt — is linked implicitly), so `-lc` makes ld fail with "cannot find
    # -lc". libm exists as a stub, so keep it. Windows only; -lc is fine and
    # implicit on Linux/Darwin.
    ${lib.optionalString stdenv.hostPlatform.isWindows ''
      substituteInPlace Makefile \
        --replace-quiet '-fuse-ld=gold' "" \
        --replace-fail 'LIBS := -lc -lm' 'LIBS := -lm'
    ''}

    # The Makefile compiles AND links C++ through $(CC) (CPP := $(CC), LD :=
    # $(CC)). mkEngine sets CC to the C driver and CXX to the C++ driver, so
    # route both through $(CXX); otherwise the C driver links without the C++
    # runtime (libc++ on Darwin) and the link fails.
    substituteInPlace Makefile \
      --replace-fail 'CPP     := $(CC)' 'CPP     := $(CXX)' \
      --replace-fail 'LD      := $(CC)' 'LD      := $(CXX)'

    # On aarch64-linux, compile/link with clang++ (see nativeBuildInputs note).
    ${lib.optionalString (stdenv.hostPlatform.isAarch64 && stdenv.hostPlatform.isLinux) ''
      substituteInPlace Makefile \
        --replace-fail 'CPP     := $(CXX)' 'CPP     := clang++' \
        --replace-fail 'LD      := $(CXX)' 'LD      := clang++'
    ''}

    # Vendor the Fathom (Syzygy prober) submodule the tarball omits. The
    # Makefile expects it at $(STB)=syzygy/src and compiles tbprobe.c (which
    # #includes tbchess.c/tbconfig.h) as C++.
    mkdir -p syzygy/src
    cp ${fathom}/src/*.c ${fathom}/src/*.h syzygy/src/
  '';

  # The Makefile writes objects/binaries to ../build, ../bin etc — i.e. into the
  # parent `source` dir, which is read-only because sourceRoot is a subdir. Make
  # it writable, then create the dirs up front so parallel make does not race
  # the Makefile's own `dirs` target (which otherwise loses to the object
  # compilations and fails with "unable to open output file '../build/*.o'").
  preBuild = ''
    chmod u+w ..
    mkdir -p ../build ../bin ../profile ../prof_data
  '';

  # Arasan loads the net at runtime from the directory of the executable
  # (options defaults nnueFile to the bare filename; globals::initGlobals
  # prepends the real exe path via derivePath) and *terminates* if it cannot be
  # opened. So the net must sit next to the installed binary in $out/bin, which
  # mkEngine's dataFiles (-> share/) cannot express. The build writes the binary
  # to ../bin/arasanx-64-<type>; install that as `arasan` alongside the net.
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    install -Dm755 ../bin/arasanx-64-* "$out/bin/arasan"
    cp ../network/arasanv5-20251222.nnue "$out/bin/"
    runHook postInstall
  '';

  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"
    out_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 10\n'; sleep 4; printf 'quit\n'; } \
      | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove' || {
      echo "FAIL: ${pname} produced no bestmove (NNUE net likely not loaded)" >&2
      echo "$out_txt" >&2; exit 1; }
    echo "ok: ${pname} speaks UCI and searches (net loaded)"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Arasan, Jon Dart's NNUE UCI chess engine, built with the ARM NEON target";
    homepage = "https://www.arasanchess.org/";
    # LICENSE is a verbatim MIT-style permissive grant: "Copyright 1994-2026 by
    # Jon Dart ... Permission is hereby granted, free of charge ... to deal in
    # the Software without restriction ...". Arasan relicensed to MIT at v14.
    license = licenses.mit;
    maintainers = [ ];
  };
}
