{ lib, mkEngine, fetchFromGitHub }:

# Demolito is a plain C engine driven by a hand-written `src/makefile`, exactly
# the shape mkEngine exists for, so it uses mkEngine rather than a bespoke
# derivation. It is Lucas Braesch's engine and is DISTINCT from his earlier
# DiscoCheck (packaged separately here).
#
# Not to be confused with the NNUE assumption sometimes made about it: the
# current tree is purely hand-crafted evaluation (src/eval.c + src/pst.c, no
# nnue.* and no net file anywhere in the source), so there is nothing to pin and
# the engine searches the instant it starts — no EVALFILE, no runtime data.

mkEngine rec {
  pname = "demolito";

  # Upstream is a rolling development repo: the binary reports VERSION="dev" and
  # the only git tag (20211004) is years stale, so — as with counter/zurichess
  # here — we pin a recent commit and give it an unstable version string rather
  # than pretend a release exists.
  version = "0-unstable-2025-12-16";

  src = fetchFromGitHub {
    owner = "lucasart";
    repo = "Demolito";
    rev = "1ad331e551c0ee7e15533557072cc605794c5615";
    hash = "sha256-LFxospgvQo5IMlZpwmmY87dbh9+iWX2j47Gi3VLp9I0=";
  };

  # The makefile lives in and compiles from src/ (its recipe is `$(CC) ...
  # ./*.c`), so the build has to run there.
  sourceRoot = "source/src";

  # `default` is the portable target; the only other, `pext`, adds -DPEXT and
  # the x86-only BMI2 pext path (guarded out of the default build). The default
  # recipe hardcodes `-march=native`, which mkEngine's stripArchFlags removes,
  # leaving a generic, reproducible build that runs on aarch64 and x86 alike.
  makeTarget = "default";
  binaries = [ "demolito" ];

  # mkEngine's default check is only a uci/uciok handshake. Demolito is HCE, not
  # NNUE, so there is no net to break, but proving it actually searches and
  # returns a move is a stronger guarantee and costs nothing here.
  installCheckPhase = ''
    runHook preInstallCheck
    bin="$out/bin/demolito"
    out_txt=$(printf 'uci\nquit\n' | "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: demolito did not answer 'uciok' to a uci handshake" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "ok: demolito speaks UCI"

    search_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 10\n'; \
      sleep 3; printf 'quit\n'; } | "$bin" | tr -d '\r')
    echo "$search_txt" | grep -q '^bestmove ' || {
      echo "FAIL: demolito returned no bestmove from 'go depth 10'" >&2
      echo "$search_txt" >&2
      exit 1
    }
    echo "ok: demolito searches and returns a bestmove"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Demolito, Lucas Braesch's hand-crafted-evaluation UCI engine in C";
    homepage = "https://github.com/lucasart/Demolito";
    # The repo's `license` file is verbatim GPL-3.0, and every source header
    # (e.g. src/main.c) reads "either version 3 of the License, or (at your
    # option) any later version", i.e. GPL-3.0-or-later.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
