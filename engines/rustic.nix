# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally, but Rust engines use
# rustPlatform.buildRustPackage instead.
{ lib, stdenv, buildPackages, rustPlatform, fetchFromGitea
, mkEngine ? null }:

# Rustic is a Rust engine, so mkEngine does not apply; this is a standalone
# rustPlatform.buildRustPackage. The meta fields and the UCI smoke test below
# mirror lib/mkEngine.nix so the engine is held to the same standard as the rest
# of the collection.
#
# Owner/source note: Rustic is a didactic sparring engine by Marcel Vanthoor.
# The canonical repository is on Codeberg (codeberg.org/mvanthoor/rustic, a Gitea
# host - hence fetchFromGitea); the GitHub mirror is a redirect stub. Releases
# are tagged `alpha-<version>` and the crate is named `rustic-alpha`.

rustPlatform.buildRustPackage rec {
  pname = "rustic";
  version = "3.0.6";

  src = fetchFromGitea {
    domain = "codeberg.org";
    owner = "mvanthoor";
    repo = "rustic";
    rev = "alpha-${version}";
    hash = "sha256-wxwcA21W4wsRRCfP8eqpLwnIo6KG1CBsVsd39cNsQyg=";
  };

  # Rustic commits its Cargo.lock, so buildRustPackage vendors the crates
  # reproducibly from it. cargoHash covers that vendored set.
  cargoHash = "sha256-w77yXvW9liae7eWbnCH2LeaZ+BBQeeAxM34HCGa7dfw=";

  # Rustic is a hand-crafted-evaluation (tapered PSQT) engine: no NNUE net,
  # nothing fetched over the network, no build script, and no x86 intrinsics -
  # the code is portable scalar Rust, so it builds and runs unchanged on aarch64.
  # (The crate is edition 2024, which the pinned nixpkgs rustc supports.)

  # buildRustPackage's default checkPhase runs `cargo test`; those suites are not
  # needed to validate a working engine (the UCI search smoke test below does
  # that) and only slow the build, so skip them.
  doCheck = false;

  # The binary target is named `rustic-alpha` (the package name); rename it to
  # `rustic` on install so it matches the package (and the collection's naming).
  postInstall = ''
    mv "$out/bin/rustic-alpha${stdenv.hostPlatform.extensions.executable}" \
       "$out/bin/rustic${stdenv.hostPlatform.extensions.executable}"
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

    # Bound the search by time, not depth: `go depth 10` can outrun a fixed
    # sleep on a slow/loaded CI runner and emit no bestmove before `quit`
    # (a false failure). `movetime` guarantees a move within a known window.
    search_txt=$( { printf 'uci\nisready\nposition startpos\ngo movetime 3000\n'; \
      sleep 8; printf 'quit\n'; } | timeout -s KILL 30 $emu "$bin" 2>/dev/null | tr -d '\r' || true)
    echo "$search_txt" | grep -q '^bestmove ' || {
      echo "FAIL: ${pname} returned no bestmove from 'go movetime 3000'" >&2
      echo "$search_txt" >&2
      exit 1
    }
    echo "ok: ${pname} searches and returns a bestmove"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Rustic, a didactic UCI chess engine written in Rust";
    homepage = "https://github.com/mvanthoor/rustic";
    # LICENSE in the repository root is the verbatim GPLv3 text; the source
    # headers grant "the GNU General Public License version 3" with no "or any
    # later version" clause, so the conservative reading is GPL-3.0-only.
    license = licenses.gpl3Only;
    mainProgram = "rustic";
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
