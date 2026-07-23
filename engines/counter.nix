# `mkEngine` is accepted and ignored: both engines/default.nix and
# test-engine.nix pass it to every engine file unconditionally.
{ lib, stdenv, buildPackages, buildGoModule, fetchFromGitHub, mkEngine ? null }:

# Counter is written in Go, so mkEngine (which is stdenv.mkDerivation plus
# Makefile fixups) does not apply. buildGoModule is used instead; the meta
# fields and the UCI smoke test below mirror lib/mkEngine.nix so this engine
# is checked to the same standard as the rest of the collection.

buildGoModule rec {
  pname = "counter";
  version = "5.5";

  # The tag list is a mess - v5.0.0 and v1.50.0 point at the same 2022 commit
  # and the newest tag (v1.55.0) is from 2024, well behind the tree. The
  # version this pin corresponds to is the `versionName` constant in
  # cmd/counter/main.go, which reads 5.5. Pinning the commit is the only way
  # to get a coherent current version.
  src = fetchFromGitHub {
    owner = "ChizhovVadim";
    repo = "CounterGo";
    rev = "de02aef5a6887b82383ae9a7d6ce0614b730155f";
    hash = "sha256-2qA+0l/LN0x0wkV5hK5vdbyKIwhcRbKA7DODKAfIL9w=";
  };

  # go.mod declares no requires at all - the engine is pure stdlib - so there
  # is no module cache to fix up.
  vendorHash = null;

  # Cross-compiling Go to Windows defaults CGO on and then fails ("cannot find
  # runtime/cgo") without a wired mingw C toolchain. Counter is pure Go, so
  # just disable cgo for the Windows cross.
  env.CGO_ENABLED = if stdenv.hostPlatform.isWindows then "0" else "1";

  # cmd/counter is the only main package; building it alone skips the various
  # training and tuning helpers under pkg/.
  subPackages = [ "cmd/counter" ];

  # The network weights (cmd/counter/n-30-5268.nn) are committed in-repo and
  # pulled in with go:embed, so unlike most modern engines there is no net to
  # pin as a separate fetchurl and no EVALFILE to thread through.

  # Upstream's test suite includes deliberately long-running search tests.
  doCheck = false;

  ldflags = [ "-s" "-w" ];

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Same handshake check mkEngine applies to the C/C++ engines: build, then
  # require 'uciok' back. Catches an engine that links but dies on startup.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    out_txt=$(printf 'uci\nquit\n' | $emu "$out/bin/counter${stdenv.hostPlatform.extensions.executable}" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: counter did not answer 'uciok' to a uci handshake" >&2
      echo "--- engine output ---" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "ok: counter speaks UCI"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Counter, Vadim Chizhov's UCI engine written in Go, with an embedded NNUE-style net";
    homepage = "https://github.com/ChizhovVadim/CounterGo";
    # Verified against the upstream LICENSE file: verbatim GPL-3.0 text.
    # The header comment in cmd/counter/main.go states "either version 3 of
    # the License, or (at your option) any later version", i.e. GPL-3.0+.
    # https://github.com/ChizhovVadim/CounterGo/blob/master/LICENSE
    license = licenses.gpl3Plus;
    mainProgram = "counter";
    # Gated off Windows: Go+cgo cross to Windows fails in nixpkgs at the Go toolchain bootstrap.
    platforms = platforms.unix;
    maintainers = [ ];
  };
}
