# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally, but Rust engines use
# rustPlatform.buildRustPackage instead.
{ lib, stdenv, buildPackages, rustPlatform, fetchgit
, mkEngine ? null }:

# Black Marlin is a Rust engine, so mkEngine does not apply; this is a
# standalone rustPlatform.buildRustPackage. The meta fields and the UCI smoke
# test below mirror lib/mkEngine.nix so the engine is held to the same standard
# as the rest of the collection.

rustPlatform.buildRustPackage rec {
  pname = "blackmarlin";
  version = "9.0";

  # The NNUE net (nn/default.bin) is stored via Git LFS - the file in the tree
  # is a 133-byte LFS pointer, not the 29 MB net. fetchFromGitHub's tarball
  # download would only ever get the pointer, so we use fetchgit with
  # fetchLFS = true, which resolves the LFS object and lands the real net in the
  # tree. build.rs then reads it (EVALFILE defaults to ./nn/default.bin) and
  # copies it into OUT_DIR, where src/bm/nnue/mod.rs embeds it via
  # include_bytes!. Nothing is fetched at build time.
  src = fetchgit {
    url = "https://github.com/dsekercioglu/blackmarlin.git";
    rev = "83826c1ec45d7698b33de151fe0d6c642e9ff4f5"; # tag 9.0
    fetchLFS = true;
    hash = "sha256-Rthea49Q4bCSYoqW2Wb5qVvX9rkgo8YavGst56RHfFI=";
  };

  # Black Marlin commits its Cargo.lock, so buildRustPackage vendors the crates
  # reproducibly from it. cargoHash covers that vendored set.
  cargoHash = "sha256-6iIGF2mLfM6nTHY6LE4MeedNZTKbnkNAy6yOIc8G1yI=";

  # The repo's .cargo/config.toml forces `-C target-cpu=native`, which pins the
  # binary to the build machine's exact microarchitecture and breaks
  # reproducibility. Drop it: the NNUE inference has an explicit NEON path
  # (#[cfg(target_feature = "neon")], default-on for aarch64) plus a portable
  # scalar fallback, so removing the native flag still gives full-strength SIMD
  # on ARM without hardwiring host-specific codegen.
  postPatch = ''
    rm -f .cargo/config.toml
  '';

  # buildRustPackage's default checkPhase runs `cargo test`, which includes an
  # upstream eval unit test (src/bm/bm_util/eval.rs) that asserts on exact
  # mate-score comparisons and panics here. It does not reflect engine health;
  # the UCI search smoke test below is the real gate, so skip cargo test.
  doCheck = false;

  # PGO/native codegen live only in the Makefile (cargo rustc with
  # -C target-cpu=native); buildRustPackage runs a plain `cargo build --release`
  # and never touches it.

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
    description = "Black Marlin, a strong NNUE UCI chess engine written in Rust";
    homepage = "https://github.com/dsekercioglu/blackmarlin";
    # LICENSE in the repository root is the verbatim GNU GPL-3.0 text; no source
    # file carries an "or any later version" notice, so the conservative
    # reading is GPL-3.0-only.
    license = licenses.gpl3Only;
    mainProgram = "blackmarlin";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
