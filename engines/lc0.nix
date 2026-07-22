{ lib, stdenv, lc0, fetchurl, makeWrapper, ... }:

# Full-strength Leela Chess Zero, distinct from the Maia family.
#
# nixpkgs' lc0 is built with the CPU (eigen) backend only, and marked broken
# on Darwin — the flag is stale, lc0 0.32.1 builds and runs on aarch64-darwin.
#
# On CPU, the BT4 competition network used at TCEC is impractically slow, so
# the default here is a distilled T1 network that gives strong play at usable
# node rates on a CPU backend. The larger net is exposed too for anyone
# rebuilding lc0 with a GPU backend, where it is far stronger.
#
# Networks are pinned by exact filename + hash. lczero.org rotates the "best"
# net over time; the update script bumps these deliberately, never silently.

let
  lc0' = lc0; # broken flag handled at nixpkgs-import level (see flake.nix)

  networks = {
    # ~150 MB, the practical default for CPU play.
    "t1-512" = {
      file = "t1-512x15x8h-distilled-swa-3395000.pb.gz";
      hash = "sha256-H9sVGeWwLgPx2SAeyOuV9kDjLMZFmk8UwOq2iQ3Al+g=";
      default = true;
    };
    # ~37 MB, for weaker hardware; faster, a little weaker.
    "t1-256" = {
      file = "t1-256x10-distilled-swa-2432500.pb.gz";
      hash = "sha256-vCemyuitNvK5qApq2dq7DW/aJbHn9IGnm8NZ4U9WNAY=";
      default = false;
    };
  };

  mkLc0 = suffix: net:
    let
      weights = fetchurl {
        url = "https://storage.lczero.org/files/networks-contrib/${net.file}";
        inherit (net) hash;
      };
      name = if net.default then "lc0" else "lc0-${suffix}";
    in
    stdenv.mkDerivation {
      pname = name;
      version = lc0'.version;
      dontUnpack = true;
      nativeBuildInputs = [ makeWrapper ];

      installPhase = ''
        runHook preInstall
        mkdir -p "$out/share/${name}"
        cp ${weights} "$out/share/${name}/${net.file}"
        makeWrapper ${lc0'}/bin/lc0 "$out/bin/${name}" \
          --add-flags "--weights=$out/share/${name}/${net.file}"
        runHook postInstall
      '';

      doInstallCheck = true;
      # Hold stdin open past the `go`: lc0 loads a ~150 MB net and initialises
      # the eigen backend before searching, and exits on EOF. An instant pipe
      # close makes it quit before it can answer bestmove — a false failure.
      installCheckPhase = ''
        out_txt=$({ printf 'uci\nisready\nposition startpos\ngo nodes 100\n'; sleep 30; printf 'quit\n'; } \
          | "$out/bin/${name}" 2>/dev/null | tr -d '\r')
        echo "$out_txt" | grep -q uciok || { echo "FAIL: ${name} no uciok" >&2; exit 1; }
        echo "$out_txt" | grep -q bestmove || { echo "FAIL: ${name} no bestmove — net likely not loaded" >&2; exit 1; }
        echo "ok: ${name} searches"
      '';

      meta = with lib; {
        description = "Leela Chess Zero with the ${suffix} network"
          + lib.optionalString net.default " (CPU-practical default)";
        homepage = "https://lczero.org";
        license = licenses.gpl3Only;
        mainProgram = name;
        platforms = platforms.unix;
      };
    };
in
lib.mapAttrs' (suffix: net: lib.nameValuePair
  (if net.default then "lc0" else "lc0-${suffix}")
  (mkLc0 suffix net))
  networks
