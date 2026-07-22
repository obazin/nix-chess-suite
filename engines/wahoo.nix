# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally, but Rust engines use
# rustPlatform.buildRustPackage instead.
{ lib, stdenv, buildPackages, rustPlatform, fetchFromGitHub
, mkEngine ? null }:

# Wahoo is a Rust engine, so mkEngine does not apply; this is a standalone
# rustPlatform.buildRustPackage. The meta fields and the UCI smoke test below
# mirror lib/mkEngine.nix so the engine is held to the same standard as the rest
# of the collection.
#
# Owner note: Wahoo is by Andrew Hockman (GitHub spamdrew128); the in-repo
# LICENSE reads "Copyright (c) 2023 Andrew Hockman".

rustPlatform.buildRustPackage rec {
  pname = "wahoo";
  version = "4.0.0";

  src = fetchFromGitHub {
    owner = "spamdrew128";
    repo = "Wahoo";
    rev = version;
    hash = "sha256-YrxbhbcQ4cussyMIMbBhWUgmYgxK0ByRXw1e1kohrvc=";
  };

  # Wahoo commits its (workspace) Cargo.lock, so buildRustPackage vendors the
  # crates reproducibly from it. cargoHash covers that vendored set.
  cargoHash = "sha256-JxS+0ejMCiKuoWOJTdsNFGOuMLZRkARPV/BrzPAvA6E=";

  # This is a cargo workspace (engine, uci_loop, datagen, tuning). The `uci_loop`
  # member is the UCI binary (it is the one with a src/main.rs that drives the
  # engine); `datagen` and `tuning` are training tools. Restrict the build to the
  # engine binary so no tooling lands in $out/bin.
  cargoBuildFlags = [ "-p" "uci_loop" ];

  # Wahoo is a hand-crafted-evaluation (HCE) engine: no NNUE net, nothing fetched
  # over the network, and no x86 intrinsics - the evaluation is portable scalar
  # Rust, so it builds and runs unchanged on aarch64.

  # buildRustPackage's default checkPhase runs `cargo test` across the workspace;
  # those suites are not needed to validate a working engine (the UCI search
  # smoke test below does that) and only slow the build, so skip them.
  doCheck = false;

  # The repo's .cargo/config.toml forces `-C target-cpu=native`, which pins the
  # binary to the build machine's exact microarchitecture and breaks
  # reproducibility. The engine is plain scalar Rust, so dropping the flag costs
  # nothing and keeps the build portable.
  #
  # The binary target is named `uci_loop`; rename it to `wahoo` on install so it
  # matches the package (and the collection's naming).
  postPatch = ''
    rm -f .cargo/config.toml
  '';

  postInstall = ''
    mv "$out/bin/uci_loop${stdenv.hostPlatform.extensions.executable}" \
       "$out/bin/wahoo${stdenv.hostPlatform.extensions.executable}"
  '';

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Same guarantee as mkEngine, plus an actual search: handshake to uciok, then
  # require a bestmove from `go depth 10`.
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
      sleep 4; printf 'quit\n'; } | $emu "$bin" | tr -d '\r')
    echo "$search_txt" | grep -q '^bestmove ' || {
      echo "FAIL: ${pname} returned no bestmove from 'go depth 10'" >&2
      echo "$search_txt" >&2
      exit 1
    }
    echo "ok: ${pname} searches and returns a bestmove"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Wahoo, a UCI chess engine written in Rust";
    homepage = "https://github.com/spamdrew128/Wahoo";
    # LICENSE in the repository root is the verbatim MIT license,
    # (c) 2023 Andrew Hockman.
    license = licenses.mit;
    mainProgram = "wahoo";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
