# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally, but Rust engines use
# rustPlatform.buildRustPackage instead.
{ lib, stdenv, buildPackages, rustPlatform, fetchFromGitHub
, mkEngine ? null }:

# Velvet is a Rust engine, so mkEngine (stdenv.mkDerivation + Makefile fixups)
# does not apply; this is a standalone rustPlatform.buildRustPackage. The meta
# fields and the UCI smoke test below mirror lib/mkEngine.nix so the engine is
# held to the same standard as the rest of the collection.

rustPlatform.buildRustPackage rec {
  pname = "velvet";
  version = "8.1.1";

  src = fetchFromGitHub {
    owner = "mhonert";
    repo = "velvet-chess";
    rev = "v${version}";
    hash = "sha256-A1+TAyjiuCUL5W2WmisM9KXF56iG3A6oR7ntV8T71Iw=";
  };

  # Velvet commits its (workspace) Cargo.lock, so buildRustPackage vendors the
  # crates reproducibly from it. cargoHash covers that vendored set.
  cargoHash = "sha256-Fk6RVV0ynhbUdzozu5J8nDh1BlHpjycpZSkclb3WZog=";

  # This is a large cargo workspace (engine, fathomrs, trainers, selfplay,
  # tournament, tuner, ...). Only the `velvet` package (the engine/ member) is
  # the UCI engine; restrict the build to it so no trainer/datagen tooling lands
  # in $out/bin.
  cargoBuildFlags = [ "-p" "velvet" ];

  # The velvet package's default feature is `fathomrs`, its Syzygy tablebase
  # prober (a C library built via fathomrs/build.rs with cc + bindgen/libclang).
  # Tablebases are strictly optional for a working engine, so drop the default
  # features to keep the build self-contained; without fathomrs no build script
  # runs at all and the engine still searches at full NNUE strength.
  buildNoDefaultFeatures = true;

  # The two NNUE nets (engine/nets/velvet_nml.qnn and velvet_rsk.qnn) are plain
  # files committed in-tree and pulled in at compile time via include_bytes!;
  # nothing is fetched over the network. The default ("normal") net is loaded at
  # startup, the risky net on demand - both are embedded.

  # buildRustPackage's default checkPhase runs `cargo test`; the workspace's test
  # suites are not needed to validate a working engine (the UCI search smoke test
  # below does that) and only slow the build, so skip them.
  doCheck = false;

  # The repo's .cargo/config.toml forces `-Ctarget-cpu=native` (and
  # CFLAGS=-march=native), which pins the binary to the build machine's exact
  # microarchitecture and breaks reproducibility. Drop it. Velvet ships a NEON
  # inference path (#[cfg(all(target_arch = "aarch64", target_feature = "neon"))]
  # in engine/src/nn/eval.rs) plus a scalar fallback, and on aarch64 `neon` is a
  # baseline target feature, so the portable build still uses SIMD on this host.
  postPatch = ''
    rm -f .cargo/config.toml
  '';

  # PGO/native codegen live only in upstream's build tooling and are never
  # engaged by buildRustPackage's plain `cargo build --release`.

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
    description = "Velvet, a strong NNUE UCI chess engine written in Rust";
    homepage = "https://github.com/mhonert/velvet-chess";
    # engine/Cargo.toml declares `license = "GPL-3.0-or-later"` and every source
    # header carries the GPL "version 3 ... or (at your option) any later
    # version" notice; LICENSE is the verbatim GPLv3 text.
    license = licenses.gpl3Plus;
    mainProgram = "velvet";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
