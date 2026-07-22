{ lib, stdenv, lc0, fetchurl, makeWrapper, ... }:

# Maia: human-like play at a target rating.
#
# The 1800-2400 band this collection targets is thinly populated in modern
# open-source engines — nearly everything maintained is 2800+, and the
# genuinely weak engines are abandoned. Maia is a better answer for sparring
# than crippling a strong engine: `UCI_LimitStrength` on Stockfish plays
# strong moves with artificial blunders injected, which trains bad instincts.
# Maia nets are trained on human games at a specific rating band, so they lose
# the way a human of that rating loses.
#
# Each rating is exposed as its own UCI engine, so a GUI sees `maia-1500` as a
# distinct opponent rather than requiring per-net configuration.
#
# One caveat worth knowing: Maia is trained to predict the move a human would
# play, not the best move, so it is deliberately weak at long time controls —
# more search does not make it much stronger. It is configured here for
# single-node search, which is how the authors intend it to be used.

let
  # nixpkgs marks lc0 broken on Darwin, but it builds and runs correctly on
  # aarch64-darwin as of 0.32.1 — verified by direct build. Worth upstreaming.
  lc0' = lc0.overrideAttrs (_: { meta = lc0.meta // { broken = false; }; });

  weightHashes = {
    "1100" = "sha256-4c8c0Mlrik+monX0uf1U7R/+v5/kRkG5/O3tMQ6WGcQ=";
    "1200" = "sha256-6tS6lT8jOucymZ68HitnU3gUhSfrz60vCsvF5MIk2Y4=";
    "1300" = "sha256-Nhlfh79HYYNLqgv4dHKxhQmnJhqdfW8ahEMmE2mnM/I=";
    "1400" = "sha256-1TU+pnZjVtrS0okgxmkvN6XzCWN2fxoxBdM7TQrwEeg=";
    "1500" = "sha256-NatvIEIdWeHfOxfFpQFpR69MZ2E2jvhARKmpx2GamgA=";
    "1600" = "sha256-0snllIWBrPS5/AsecgxdwP5kzoDPxKI50/ikLhF2yHY=";
    "1700" = "sha256-0nfqzXktNAowq7Rk3GUSclTmXKxXq8oX+sxGmIm5ZHg=";
    "1800" = "sha256-ADGtfEJWsf0J++vShBjWRNaLJs0qRd9JZ8z1x+ycSWU=";
    "1900" = "sha256-4vVl9C182fEiVX5txOuE5buu3O2h1ATcSF02EcfJehI=";
  };

  # Pinned to a specific commit rather than master: the weights are research
  # artefacts and should not silently change under a rating label.
  maiaRev = "749204cf5979ce7f8b0412e804a4ee7c83c49ff8";

  mkMaia = rating: hash:
    let
      weights = fetchurl {
        url = "https://github.com/CSSLab/maia-chess/raw/${maiaRev}/maia_weights/maia-${rating}.pb.gz";
        inherit hash;
      };
    in
    stdenv.mkDerivation {
      pname = "maia-${rating}";
      version = "1.0";

      dontUnpack = true;
      nativeBuildInputs = [ makeWrapper ];

      installPhase = ''
        runHook preInstall
        mkdir -p "$out/share/maia-${rating}"
        cp ${weights} "$out/share/maia-${rating}/maia-${rating}.pb.gz"

        # `policyhead` is lc0's single-shot policy mode: it returns the move
        # the network considers most human-like without running a search tree.
        # That is exactly Maia's design intent — tree search would make it
        # stronger but far less human, defeating the point. Older Maia docs
        # recommend `--nodes=1` for this, but that flag was removed from lc0
        # and `policyhead` is the current equivalent.
        makeWrapper ${lc0'}/bin/lc0 "$out/bin/maia-${rating}" \
          --add-flags "policyhead" \
          --add-flags "--weights=$out/share/maia-${rating}/maia-${rating}.pb.gz"
        runHook postInstall
      '';

      doInstallCheck = true;
      installCheckPhase = ''
        out_txt=$(printf 'uci\nquit\n' | "$out/bin/maia-${rating}" | tr -d '\r')
        echo "$out_txt" | grep -q uciok || {
          echo "FAIL: maia-${rating} did not answer uciok" >&2
          echo "$out_txt" >&2
          exit 1
        }
        echo "ok: maia-${rating} speaks UCI"
      '';

      meta = with lib; {
        description = "Lc0 with the Maia ${rating} network, playing like a human rated ~${rating}";
        homepage = "https://maiachess.com";
        # Engine is GPL-3.0 (lc0); the weights are released under the
        # maia-chess repository's own terms.
        license = licenses.gpl3Only;
        mainProgram = "maia-${rating}";
        platforms = platforms.unix;
      };
    };
in
lib.mapAttrs' (rating: hash: lib.nameValuePair "maia-${rating}" (mkMaia rating hash)) weightHashes
