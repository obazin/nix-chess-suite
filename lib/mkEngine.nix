{ lib, stdenv, buildPackages, windows }:

# Generic builder for UCI chess engines.
#
# Most engines here are plain Makefile projects that predate any notion of
# cross-compilation or non-x86 hardware. The recurring problems are:
#   * hardcoded -march=/-msse*/-mpopcnt flags that break on aarch64
#   * hardcoded CC=gcc, ignoring $CXX
#   * no install target
#   * NNUE nets fetched over the network at build time (sandbox-forbidden)
#
# mkEngine centralises the fixes so individual engine files stay small.

{ pname
, version
, src
, meta ? { }

  # Subdirectory holding the Makefile, if not the source root.
, sourceRoot ? null

  # Make target and extra flags.
, makeTarget ? null
, makeFlags ? [ ]

  # Name(s) of the binary produced by the build, relative to the build dir.
  # The first is installed as `bin/${pname}`; the rest as-is.
, binaries ? [ pname ]

  # Strip x86-only codegen flags from Makefiles. Safe to leave on for aarch64;
  # on x86_64 it costs a little speed but buys reproducibility across CPUs.
  # Set to false for engines with a proper arch-detection target.
, stripArchFlags ? true

  # Extra data installed to $out/share/${pname} (books, personalities, nets).
, dataFiles ? [ ]

  # NNUE net pinned as a separate fetchurl. Copied into the source tree and
  # exposed as $EVALFILE, which nearly every modern engine honours.
, evalFile ? null
, evalFileName ? null

, nativeBuildInputs ? [ ]
, buildInputs ? [ ]
, ...
}@args:

let
  # Flags that are meaningless or fatal outside x86_64.
  archFlagPattern = lib.concatStringsSep "|" [
    "-march=[a-z0-9._-]*"
    "-mtune=[a-z0-9._-]*"
    "-msse[0-9.a-z]*"
    "-mpopcnt"
    "-mavx[0-9a-z]*"
    "-mbmi[0-9]*"
    "-mssse3"
    "-m64"
    "-flto=[a-z0-9]*"
  ];

  passthruArgs = builtins.removeAttrs args [
    "pname" "version" "src" "meta" "sourceRoot" "makeTarget" "makeFlags"
    "binaries" "stripArchFlags" "dataFiles" "evalFile" "evalFileName"
    "nativeBuildInputs" "buildInputs"
  ];
in
stdenv.mkDerivation (passthruArgs // {
  inherit pname version src nativeBuildInputs;
  # On a mingw (Windows) cross, POSIX threads come from winpthreads: it supplies
  # <pthread.h> and libpthread so the many engines that `#include <pthread.h>`
  # and link -lpthread build unchanged.
  buildInputs = buildInputs
    ++ lib.optional stdenv.hostPlatform.isWindows windows.pthreads;

  # Force-link the libraries that mingw builds routinely need but engine
  # Makefiles don't name (they assume Linux): winpthreads (-lpthread) for
  # pthread_* callers, Winsock (-lws2_32) for socket users, and winmm
  # (-lwinmm) for the multimedia timer (timeGetTime/timeBeginPeriod). All
  # harmless when unused; only added for the Windows cross.
  #
  # `-static` makes the .exe self-contained so it runs on a stock Windows box:
  # nixpkgs' mingw gcc ships libstdc++/libgcc/libwinpthread as static + import
  # libs, NOT as distributable DLLs, so a dynamically-linked build imports
  # libstdc++-6.dll / libgcc_s_seh-1.dll that don't exist to ship. Static links
  # them in; the system import libs (ws2_32, winmm, kernel32) still resolve to
  # the always-present Windows DLLs. This is what makes the release binaries
  # usable without a Nix/mingw toolchain.
  NIX_LDFLAGS = lib.optionalString stdenv.hostPlatform.isWindows
    "-static -lpthread -lws2_32 -lwinmm";
} // lib.optionalAttrs (sourceRoot != null) {
  inherit sourceRoot;
} // {

  # Pin the net into the tree before the build can try to curl it.
  # evalFileName may include a subdirectory (e.g. weights/net.bin), so create
  # the parent — a flat `cp` into a non-existent dir would fail.
  postUnpack = lib.optionalString (evalFile != null) ''
    mkdir -p "$sourceRoot/$(dirname "${evalFileName}")"
    cp ${evalFile} "$sourceRoot/${evalFileName}"
  '' + (args.postUnpack or "");

  postPatch = ''
    # The unpacked Nix source is read-only. Several engines' Makefiles write
    # objects into sibling dirs (e.g. build/ into ../src), which then fails
    # with EACCES. Make the whole extracted tree writable up front.
    chmod -R u+w . 2>/dev/null || true
  '' + lib.optionalString stripArchFlags ''
    echo "mkEngine: stripping x86-only codegen flags from makefiles"
    for mk in Makefile makefile GNUmakefile Makefile.* *.mk make.sh; do
      [ -f "$mk" ] || continue
      sed -i -E 's/(${archFlagPattern})//g' "$mk"
    done
  '' + lib.optionalString stdenv.hostPlatform.isWindows ''
    echo "mkEngine: stripping Linux-only link libs (-lrt/-ldl) for the mingw build"
    for mk in Makefile makefile GNUmakefile Makefile.* *.mk make.sh; do
      [ -f "$mk" ] || continue
      # librt (clock/timers) and libdl (dlopen) are folded into the Windows CRT
      # / not applicable; the tokens just make the mingw linker fail.
      sed -i -E 's/-l(rt|dl)\b//g' "$mk"
    done
    # MSVC-oriented sources #include <Windows.h>; mingw's SDK header is the
    # lowercase <windows.h>, and the Nix store is case-sensitive, so normalise.
    grep -rlZ '<Windows.h>' --include='*.c' --include='*.cc' --include='*.cpp' --include='*.cxx' --include='*.h' --include='*.hpp' --include='*.hh' --include='*.hxx' . 2>/dev/null \
      | xargs -0 -r sed -i 's/<Windows.h>/<windows.h>/g' || true

    # The Fruit lineage's Windows input-poll fast path peeks at stdin->_cnt, a
    # field the old MSVCRT FILE had but the mingw-UCRT FILE does not. The
    # PeekNamedPipe path right below it does the real detection, so neutralise
    # the peek (`if (0 > 0)`). Harmless where the idiom is absent.
    grep -rlZ 'stdin->_cnt' --include='*.c' --include='*.cc' --include='*.cpp' --include='*.cxx' . 2>/dev/null \
      | xargs -0 -r sed -i 's/stdin->_cnt/0/g' || true

    # Several engines have working Windows code paths whose Makefiles build with
    # -Werror and then trip a benign mingw warning (e.g. printf %d for a DWORD
    # in a POSIX/Windows shim). Turn warnings-as-errors off for the cross so
    # those build. NB: do NOT add -Wno-format here — it disables -Wformat, which
    # makes the stdenv's -Werror=format-security hardening fail with
    # "-Wformat-security ignored without -Wformat" and breaks every build.
    # Append (don't replace) so an engine's own NIX_*FLAGS survive.
    export NIX_CFLAGS_COMPILE="''${NIX_CFLAGS_COMPILE:-} -Wno-error"
  '' + ''
    # Respect the Nix toolchain rather than a hardcoded gcc. targetPrefix is
    # what makes the mingw cross-build work.
    export CC="${stdenv.cc.targetPrefix}cc"
    export CXX="${stdenv.cc.targetPrefix}c++"
  '' + (args.postPatch or "");

  makeFlags = makeFlags
    ++ lib.optional (makeTarget != null) makeTarget
    ++ [
      "CC=${stdenv.cc.targetPrefix}cc"
      "CXX=${stdenv.cc.targetPrefix}c++"
    ]
    ++ lib.optional (evalFile != null) "EVALFILE=${evalFileName}";

  # Almost none of these engines ship an install target. On a mingw cross the
  # compiler appends .exe to the output name, so look for the built file with
  # the platform's executable extension (empty on unix, ".exe" on Windows).
  installPhase = args.installPhase or ''
    runHook preInstall
    mkdir -p "$out/bin"
    ${lib.concatMapStringsSep "\n" (b: ''
      src="${b}${stdenv.hostPlatform.extensions.executable}"
      [ -e "$src" ] || src="${b}"
      install -Dm755 "$src" "$out/bin/$(basename "${b}")${stdenv.hostPlatform.extensions.executable}"
    '') binaries}
    ${lib.optionalString (binaries != [ ] && builtins.head binaries != pname) ''
      ln -sf "$out/bin/$(basename "${builtins.head binaries}")${stdenv.hostPlatform.extensions.executable}" \
             "$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"
    ''}
    ${lib.optionalString (dataFiles != [ ]) ''
      mkdir -p "$out/share/${pname}"
      ${lib.concatMapStringsSep "\n" (f: ''cp -r "${f}" "$out/share/${pname}/"'') dataFiles}
    ''}
    runHook postInstall
  '';

  # Smoke-test the UCI handshake. This catches the common failure where an
  # engine builds but crashes instantly on a missing net or data file.
  #
  # Cross-built Windows binaries run under Wine when available; note that
  # Wine emits CRLF, hence the tr.
  doInstallCheck = args.doInstallCheck or
    (stdenv.hostPlatform.emulatorAvailable buildPackages);

  installCheckPhase = args.installCheckPhase or ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    out_txt=$(printf 'uci\nquit\n' | $emu "$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok' to a uci handshake" >&2
      echo "--- engine output ---" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "ok: ${pname} speaks UCI"
    runHook postInstallCheck
  '';

  enableParallelBuilding = args.enableParallelBuilding or true;

  meta = {
    mainProgram = pname;
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  } // meta;
})
