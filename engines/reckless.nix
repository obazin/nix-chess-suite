# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally, but Rust engines use
# rustPlatform.buildRustPackage instead.
{ lib, stdenv, buildPackages, rustPlatform, fetchFromGitHub, fetchurl
, mkEngine ? null }:

# Reckless is a Rust engine, so mkEngine (stdenv.mkDerivation + Makefile fixups)
# does not apply; this is a standalone rustPlatform.buildRustPackage. The meta
# fields and the UCI smoke test below mirror lib/mkEngine.nix so the engine is
# held to the same standard as the rest of the collection.

let
  # NNUE net. build/build.rs hardcodes NETWORK_NAME = "v54-5478683c.nnue" for
  # this release and, unless EVALFILE is set, curls it from
  # github.com/codedeliveryservice/RecklessNetworks at build time - which the
  # Nix sandbox forbids. We pin the exact net as a fetchurl and point EVALFILE
  # at it, so build.rs takes the "already have it" path and never touches the
  # network. The net is embedded verbatim via include_bytes!(env!("MODEL")).
  net = fetchurl {
    url = "https://github.com/codedeliveryservice/RecklessNetworks/releases/download/networks/v54-5478683c.nnue";
    hash = "sha256-VHhoPLG6ur3imujylGipmEZyZUj8ag7VTKxAq204778=";
  };
in
rustPlatform.buildRustPackage rec {
  pname = "reckless";
  version = "0.9.0";

  src = fetchFromGitHub {
    owner = "codedeliveryservice";
    repo = "Reckless";
    rev = "v${version}";
    hash = "sha256-sO3MQBv1v71/gtok93pqMXQiGPjMLRZX+WQYBTVrB/0=";
  };

  # Reckless commits its Cargo.lock, so buildRustPackage vendors the crates
  # reproducibly from it. cargoHash covers that vendored set.
  cargoHash = "sha256-5Ohn3+++kPqSWyvr5oRyE98qtAY4ba6djVHHpOlWkRg=";

  # The default feature set pulls in `syzygy`, whose build script runs bindgen
  # over Fathom (needs libclang) and shells out to `clang` to compile the C
  # prober. Tablebases are strictly optional for a working engine, so we drop
  # the feature to keep the build self-contained; the engine still searches and
  # plays at full NNUE strength.
  buildNoDefaultFeatures = true;

  # Point the build at the pinned net instead of letting build.rs curl it.
  # MODEL (the include_bytes! target) is derived from EVALFILE when set.
  EVALFILE = net;

  # Upstream's release build is PGO-driven, but only via the Makefile's `pgo`
  # target (cargo-pgo: instrument, run bench, optimise). buildRustPackage does a
  # plain `cargo build --release`, so PGO is simply never engaged - which is
  # what we want: PGO runs the half-built binary mid-build and would break
  # reproducibility and cross-compilation.

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Same guarantee as mkEngine, plus an actual search: handshake to uciok, then
  # require a bestmove from `go depth 10`. A missing/incompatible net passes
  # the handshake but dies on `go`, so this catches net breakage too.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"

    out_txt=$(printf 'uci\nquit\n' | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok' to a uci handshake" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "ok: ${pname} speaks UCI"

    search_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 10\n'; \
      sleep 3; printf 'quit\n'; } | $emu "$bin" | tr -d '\r')
    echo "$search_txt" | grep -q '^bestmove ' || {
      echo "FAIL: ${pname} returned no bestmove from 'go depth 10'" >&2
      echo "$search_txt" >&2
      exit 1
    }
    echo "ok: ${pname} searches and returns a bestmove"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Reckless, a strong NNUE UCI engine in Rust; TCEC Season 29 Superfinalist";
    homepage = "https://github.com/codedeliveryservice/Reckless";
    # LICENSE in the repository root is the verbatim GNU AGPL-3.0 text.
    license = licenses.agpl3Only;
    mainProgram = "reckless";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
