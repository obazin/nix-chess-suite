# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally. Dumb is written in the D
# language, so mkEngine (stdenv.mkDerivation + Makefile fixups for C engines)
# does not apply. This is a plain stdenv.mkDerivation that drives the LDC
# (LLVM-based D) compiler directly. The meta fields and the UCI smoke test
# below mirror lib/mkEngine.nix so the engine is held to the same standard.
{ lib, stdenv, buildPackages, fetchFromGitHub, ldc, mkEngine ? null }:

# Dumb is Richard Delorme's slim, classical (no-NNUE) D engine. There is no
# neural net to pin: the whole evaluator is hand-written in eval.d, so the build
# is fully self-contained from source.
#
# We invoke ldc2 directly rather than via the upstream Makefile because that
# Makefile's default path targets `-mcpu=native` and, for its `bmi`/`pgo`
# targets, x86-only features (`-mattr=+bmi2`, pext intrinsics). The plain `dumb`
# target is already the "portable, no flto, no pgo" build; we reproduce its LDC
# flags (SFLAGS) minus `-mcpu=native` so the result is a clean, portable
# aarch64 build. `-w` (warnings-as-errors) is dropped: LDC 1.41 ships a newer
# D frontend than upstream tested against and emits new deprecation warnings
# that would otherwise fail an otherwise-correct build.
stdenv.mkDerivation rec {
  pname = "dumb";
  version = "2.3";

  src = fetchFromGitHub {
    owner = "abulmo";
    repo = "Dumb";
    rev = "v${version}";
    hash = "sha256-yNhPPj73WWVdItAE+qA3hkpjBjiH4kbdfP/Ryo5CJ+Q=";
  };

  nativeBuildInputs = [ ldc ];

  # LDC needs a writable HOME for its temp/config lookups inside the sandbox.
  buildPhase = ''
    runHook preBuild
    cd src
    export HOME="$TMPDIR"
    # SRC order from the upstream Makefile; D compiles all modules in one go.
    ldc2 -O3 -release -boundscheck=off -singleobj \
      -of=dumb dumb.d util.d board.d eval.d move.d search.d
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 dumb "$out/bin/dumb${stdenv.hostPlatform.extensions.executable}"
    runHook postInstall
  '';

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Same guarantee as mkEngine, plus a real search: handshake to uciok, then
  # require a bestmove from `go depth 8`. Quitting immediately would cancel the
  # search and yield a false failure, so we sleep before sending quit.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"

    out_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 8\n'; \
      sleep 4; printf 'quit\n'; } | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok' to a uci handshake" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "$out_txt" | grep -q '^bestmove ' || {
      echo "FAIL: ${pname} returned no bestmove from 'go depth 8'" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "ok: ${pname} speaks UCI and searches"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Dumb, Richard Delorme's compact classical UCI chess engine written in D";
    homepage = "https://github.com/abulmo/Dumb";
    # LICENSE in the repo root is the verbatim MIT text, "Copyright (c) 2017
    # Richard Delorme". https://github.com/abulmo/Dumb/blob/master/LICENSE
    license = licenses.mit;
    mainProgram = "dumb";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
