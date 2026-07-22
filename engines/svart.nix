# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally, but Rust engines use
# rustPlatform.buildRustPackage instead.
{ lib, stdenv, buildPackages, rustPlatform, fetchFromGitHub
, mkEngine ? null }:

# Svart is a Rust engine, so mkEngine does not apply; this is a standalone
# rustPlatform.buildRustPackage. The meta fields and the UCI smoke test below
# mirror lib/mkEngine.nix so the engine is held to the same standard as the rest
# of the collection.
#
# Owner note: the canonical repository is github.com/1337crisis/svart (the
# author formerly published as crippa1337 - the in-repo LICENSE is still
# copyright "crippa1337"). This is NOT the squatted github.com/crippa1337/svart.

rustPlatform.buildRustPackage rec {
  pname = "svart";
  version = "6.0.0";

  src = fetchFromGitHub {
    owner = "1337crisis";
    repo = "svart";
    rev = "v${version}";
    hash = "sha256-Egw68OfV1v8K/CiShnC4NYmiCZRPjyg/Rtzck9tzaaI=";
  };

  # Svart commits its (workspace) Cargo.lock, so buildRustPackage vendors the
  # crates reproducibly from it. cargoHash covers that vendored set.
  cargoHash = "sha256-ILbMT9n5qqT0SzgKqSI82YkE/wNtz2rGpRwQ17Vb7q0=";

  # This is a cargo workspace (engine, datagen). Only `engine` is the UCI
  # engine; `datagen` is a training-data tool that pulls in extra crates
  # (tabled, chrono, ctrlc, ...). Restrict the build to the engine.
  cargoBuildFlags = [ "-p" "engine" ];

  # The four NNUE tensors (engine/src/body/nnue/net/*.bin) are plain files
  # committed in-tree and pulled in at compile time via include_bytes! /
  # transmute - no x86 intrinsics, no network access. The engine builds and
  # runs unchanged on aarch64.

  # The repo's .cargo/config.toml forces `-C target-cpu=native`, which pins the
  # binary to the build machine's exact microarchitecture and breaks
  # reproducibility. The inference is plain scalar Rust (no target-gated SIMD),
  # so dropping the flag costs nothing and keeps the build portable.
  #
  # The crate's binary target is named `engine`; rename it to `svart` on install
  # so it matches the package (and the collection's naming). PGO/native codegen
  # live only in the Makefile and are never engaged by `cargo build --release`.
  postPatch = ''
    rm -f .cargo/config.toml
  '';

  postInstall = ''
    mv "$out/bin/engine${stdenv.hostPlatform.extensions.executable}" \
       "$out/bin/svart${stdenv.hostPlatform.extensions.executable}"
  '';

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
    description = "Svart, a strong NNUE UCI chess engine written in Rust";
    homepage = "https://github.com/1337crisis/svart";
    # LICENSE in the repository root is the verbatim MIT license (c) 2023
    # crippa1337 (the author's former handle).
    license = licenses.mit;
    mainProgram = "svart";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
