# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally, but Rust engines use
# rustPlatform.buildRustPackage instead.
{ lib, stdenv, buildPackages, rustPlatform, fetchFromGitHub
, mkEngine ? null }:

# Carp is a Rust engine, so mkEngine (stdenv.mkDerivation + Makefile fixups)
# does not apply; this is a standalone rustPlatform.buildRustPackage. The meta
# fields and the UCI smoke test below mirror lib/mkEngine.nix so the engine is
# held to the same standard as the rest of the collection.

rustPlatform.buildRustPackage rec {
  pname = "carp";
  version = "3.0.1";

  src = fetchFromGitHub {
    owner = "dede1751";
    repo = "carp";
    rev = "v${version}";
    hash = "sha256-UFVPQ1IYWnY3cjGGnEMAXjThOWXDux2ASsQ5qemC9V8=";
  };

  # Carp commits its Cargo.lock, so buildRustPackage vendors the crates
  # reproducibly from it. cargoHash covers that vendored set.
  cargoHash = "sha256-qZLJnyLB4kti8cXMh2v08oKrVGG+tRjKqdS+azi7Y5c=";

  # This is a cargo workspace (chess, carp, carp-tools). Only the `carp`
  # member is the UCI engine; `carp-tools` is the datagen binary. Restrict the
  # build/install to the engine so no datagen binary lands in $out/bin.
  cargoBuildFlags = [ "-p" "carp" ];

  # buildRustPackage's default checkPhase runs `cargo test`, which pulls in the
  # syzygy probe unit tests (carp/src/syzygy/probe.rs). Those assert against
  # results that only hold with Syzygy tablebase files present on disk, so they
  # panic in the sandbox. They exercise an optional feature we do not ship; the
  # engine itself is validated by the UCI search smoke test below, so skip them.
  doCheck = false;

  # The NNUE net (bins/net.bin) and every other table (magics, king/knight/pawn
  # attacks, LMR) are plain files committed in-tree and pulled in at compile
  # time via include_bytes!; nothing is fetched over the network. build.rs also
  # regenerates bins/lmr.bin into the (writable) unpacked source before it is
  # embedded. The optional `syzygy` feature (Fathom via cc + bindgen/libclang)
  # is off by default, so the default build is fully self-contained.

  # Upstream's release build is PGO-driven and only through the makefile
  # (cargo rustc with -C profile-generate / -C profile-use plus
  # -C target-cpu=native). buildRustPackage runs a plain `cargo build --release`
  # and never touches the makefile, so PGO is inert and no native-only codegen
  # is requested - which is what we want: PGO runs the half-built binary
  # mid-build and would break reproducibility and cross-compilation, and the
  # NNUE/movegen code is portable (transmute over include_bytes!, no x86
  # intrinsics), so it builds and runs on aarch64 too.

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
    description = "Carp, a didactic NNUE UCI chess engine written in Rust";
    homepage = "https://github.com/dede1751/carp";
    # LICENSE in the repository root is the verbatim GNU GPL-3.0 text; no source
    # file carries an "or any later version" notice, so the conservative
    # reading is GPL-3.0-only.
    license = licenses.gpl3Only;
    mainProgram = "carp";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
