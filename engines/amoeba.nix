# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally. Amoeba is written in the D
# language, so mkEngine (stdenv.mkDerivation + Makefile fixups for C engines)
# does not apply. This is a plain stdenv.mkDerivation driving the LDC
# (LLVM-based D) compiler directly. The meta fields and the UCI smoke test
# below mirror lib/mkEngine.nix so the engine is held to the same standard.
{ lib, stdenv, buildPackages, fetchFromGitHub, ldc, mkEngine ? null }:

# Amoeba is Richard Delorme's classical (no-NNUE) D engine; the evaluator lives
# in eval.d/weight.d, so there is no net to pin and the build is fully
# self-contained.
#
# We invoke ldc2 directly instead of using the upstream Makefile. The Makefile's
# default POPCOUNT=true path appends x86-only codegen (`-mattr=+sse4.2,+popcnt`)
# which is fatal on aarch64, and its `fast` target runs a PGO cycle (build a
# throwaway binary, run perft/bench, rebuild) that breaks sandbox
# reproducibility. We reproduce the LDC "slow"/portable flag set instead:
# `-O -release -boundscheck=off`, with POPCOUNT disabled so no x86 attributes
# are emitted (the source falls back to a portable software popcount when the
# `withPopCount` version is not set). `-preview=intpromote` is kept because it
# is a frontend semantics flag the code was written against; `-w`
# (warnings-as-errors) is dropped since LDC 1.41's newer D frontend emits new
# deprecation warnings that would fail an otherwise-correct build.
stdenv.mkDerivation rec {
  pname = "amoeba";
  version = "3.4";

  src = fetchFromGitHub {
    owner = "abulmo";
    repo = "amoeba";
    rev = "v${version}";
    hash = "sha256-uWXzaG2ewAU9t0XJ23PTyhttZJkrQgc+z+LccPD7j4Y=";
  };

  nativeBuildInputs = [ ldc ];

  postPatch = ''
    # LDC 1.41's D frontend is stricter about shared-constancy than the one
    # Amoeba was written against: a `shared class Lock` nested inside the
    # non-shared `Message` class is now rejected ("nested type shared(Lock)
    # should have the same or weaker constancy as enclosing type"). The Lock is
    # only ever used as a monitor via `synchronized (lock)`, which works on an
    # ordinary class instance, so dropping the redundant `shared` qualifier is
    # behaviour-preserving and unblocks the build.
    substituteInPlace src/util.d \
      --replace-fail 'shared class Lock {};' 'class Lock {};'
  '';

  buildPhase = ''
    runHook preBuild
    cd src
    export HOME="$TMPDIR"
    # SRC list from the upstream Makefile; D compiles all modules together.
    ldc2 -O -release -boundscheck=off -singleobj -preview=intpromote \
      -of=amoeba \
      amoeba.d board.d eval.d kpk.d move.d search.d tt.d uci.d util.d weight.d
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 amoeba "$out/bin/amoeba${stdenv.hostPlatform.extensions.executable}"
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
    description = "Amoeba, Richard Delorme's classical UCI chess engine written in D";
    homepage = "https://github.com/abulmo/amoeba";
    # LICENSE in the repo root is the verbatim GNU GPL-3.0 text. Source headers
    # carry no "or any later version" clause, so this is read as GPL-3.0-only.
    # https://github.com/abulmo/amoeba/blob/master/LICENSE
    license = licenses.gpl3Only;
    mainProgram = "amoeba";
    # Gated off Windows: D (ldc) cross to mingw is not wired up (as with dumb).
    platforms = platforms.unix;
    maintainers = [ ];
  };
}
