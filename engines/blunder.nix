# `mkEngine` is accepted and ignored: both engines/default.nix and
# test-engine.nix pass it to every engine file unconditionally.
{ lib, stdenv, buildPackages, buildGoModule, fetchFromGitHub, mkEngine ? null }:

# Blunder is written in Go, so mkEngine (stdenv + Makefile fixups) does not
# apply; buildGoModule does the job, following the pattern in counter.nix. It is
# Christian Dean's engine — a DIFFERENT author and codebase from the other Go
# engines here (Counter, Zurichess). Its evaluation is hand-crafted (tuned PST +
# terms in engine/evaluation.go), so there is no NNUE net to pin. The opening
# book is an optional UCI feature (UseBook, default false), so the engine plays
# straight out of the box with no runtime data.

buildGoModule rec {
  pname = "blunder";
  version = "8.5.5";

  src = fetchFromGitHub {
    owner = "algerbrex";
    repo = "blunder";
    rev = "v${version}";
    hash = "sha256-VIQL78Xt5EnhTpo8hre+pKPmNWk0Dv95KKcgJ+uQn+c=";
  };

  # Unlike Counter/Zurichess (pure stdlib), Blunder pulls in golang.org/x/exp,
  # so the module set must be vendored and checksummed. go.sum is committed, so
  # buildGoModule fetches deterministically against this hash.
  vendorHash = "sha256-EprLs5uJUOc57zkV1PBLvli/Y5Khhc4PTOpjTqSqyLs=";

  # The main package is blunder/main.go; building it alone skips the tuner/
  # training helpers, which pull in extra deps and are not part of the engine.
  subPackages = [ "blunder" ];

  ldflags = [ "-s" "-w" ];

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Same guarantee as the C engines: handshake to uciok, then require an actual
  # bestmove from a real search. Blunder is HCE so there is no net to fail, but
  # this proves the binary links and plays rather than merely answering UCI.
  #
  # Blunder needs careful driving, in two independent ways:
  #  1. Its UCI reader mis-parses a pipelined burst — feeding all commands in
  #     one write leaves it spinning at 100% CPU without starting a search.
  #     Fed one line at a time with a pause between each, it searches normally.
  #  2. It does not terminate on `quit` (it busy-waits rather than exiting).
  #     So the check must NOT depend on the process exiting.
  # Both invocations are therefore drip-fed AND wrapped in `timeout`, and the
  # result is judged purely from captured stdout — timeout killing the spinning
  # process is expected, not a failure. (coreutils `timeout` is in stdenv.)
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/blunder${stdenv.hostPlatform.extensions.executable}"

    out_txt=$( { printf 'uci\n';                 sleep 0.6; \
                 printf 'isready\n';              sleep 0.6; \
                 printf 'ucinewgame\n';           sleep 0.6; \
                 printf 'position startpos\n';    sleep 0.6; \
                 printf 'go movetime 3000\n';     sleep 18; \
                 printf 'quit\n';                 sleep 0.5; } \
               | timeout -s KILL 30 $emu "$bin" 2>/dev/null | tr -d '\r' || true)

    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: blunder did not answer 'uciok'" >&2; echo "$out_txt" >&2; exit 1
    }
    echo "$out_txt" | grep -q '^bestmove ' || {
      echo "FAIL: blunder returned no bestmove from 'go movetime 3000'" >&2
      echo "$out_txt" >&2; exit 1
    }
    echo "ok: blunder speaks UCI and searches"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Blunder, Christian Dean's hand-crafted-evaluation UCI engine written in Go";
    homepage = "https://github.com/algerbrex/blunder";
    # Verified against the upstream LICENSE file: verbatim MIT text,
    # "Copyright (c) 2022 Christian Dean".
    # https://github.com/algerbrex/blunder/blob/main/LICENSE
    license = licenses.mit;
    mainProgram = "blunder";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
