{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub }:

# Wukong — Code Monkey King's (Maksim Korzh) didactic 0x88 engine, a single
# self-contained wukong.c. This is the C engine, NOT the separate WukongJS
# JavaScript project. Untagged upstream, so the head commit is pinned.
#
# The engine reports its UCI name as "chess_0x88" but is a normal UCI engine.
# It is single-threaded, pure ISO C with only POSIX headers (sys/time.h,
# sys/select.h) and no arch-specific flags.

mkEngine rec {
  pname = "wukong";
  version = "1.0-unstable-2020-12-19";

  src = fetchFromGitHub {
    owner = "maksimKorzh";
    repo = "wukong";
    rev = "1b6e2c668556436a041dec3b3e25d9db6b453824";
    hash = "sha256-l6p0W5x7YhyB2I4J86b5D6BVEe5uVAxoZJHlC93DAts=";
  };

  sourceRoot = "source/src";

  # No makefile is used: upstream's makefile compiles both a native gcc target
  # and an x86_64-w64-mingw32 Windows target in one recipe, and the mingw
  # cross-compiler is not present. Build the single translation unit directly
  # with the toolchain's cc, matching upstream's `-Ofast`.
  stripArchFlags = false;
  buildPhase = ''
    runHook preBuild
    $CC -Ofast wukong.c -o wukong
    runHook postBuild
  '';

  binaries = [ "wukong" ];

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Wukong prints uciok on startup and again on `uci`. Its `go depth N` parser
  # reads a SINGLE digit (`*ptr - '0'`), so depth must be 1-9 — depth 8 is used
  # (plenty for this ~1900 engine). It exits on quit.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/wukong${stdenv.hostPlatform.extensions.executable}"

    out_txt=$( { printf 'uci\n';              sleep 0.5; \
                 printf 'isready\n';           sleep 0.5; \
                 printf 'position startpos\n'; sleep 0.5; \
                 printf 'go depth 8\n';        sleep 5; \
                 printf 'quit\n';              sleep 0.5; } \
               | timeout -s KILL 30 $emu "$bin" 2>/dev/null | tr -d '\r' || true)

    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: wukong did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1; }
    echo "$out_txt" | grep -q '^bestmove ' || {
      echo "FAIL: wukong returned no bestmove from 'go depth 8'" >&2
      echo "$out_txt" >&2; exit 1; }
    echo "ok: wukong speaks UCI and searches"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Wukong, Code Monkey King's didactic 0x88 UCI engine in a single C file (the C engine, not WukongJS)";
    homepage = "https://github.com/maksimKorzh/wukong";
    # LICENCE in the repo root (British spelling) is verbatim MIT,
    # "Copyright (c) 2020 Maksym Korzh".
    # https://github.com/maksimKorzh/wukong/blob/master/LICENCE
    license = licenses.mit;
    maintainers = [ ];
  };
}
