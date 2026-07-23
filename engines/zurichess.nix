{ lib, stdenv, buildGoModule, buildPackages, fetchgit, ... }:

# Zurichess is Go, not a hand-rolled Makefile, so none of mkEngine's fixups
# apply and buildGoModule does the job instead. The UCI smoke test below is
# copied from lib/mkEngine.nix so the guarantee is the same as for every other
# engine here.

let
  # The engine's only dependency, split out of the main repo in 2018. It is
  # vendored by hand: upstream predates go.sum, so `go mod download` would
  # refuse the module for want of a checksum, and a `replace` onto a store
  # path keeps the build entirely offline.
  board = fetchgit {
    url = "https://bitbucket.org/zurichess/board.git";
    rev = "f39ccb08867eb5a81e9a8fa5ab4956608d92196b"; # v1.0.0
    hash = "sha256-6yKXZmY05WltyT3qvc+42WLJn6uCZOrSUOReTAPU1Hs=";
  };
in
buildGoModule rec {
  pname = "zurichess";
  # Upstream never tagged; releases are named after Swiss cantons in the
  # changelog. This is the last commit on master, in the "nidwalden" cycle.
  version = "0-unstable-2018-11-24";

  # Bitbucket dropped Mercurial in 2020, but zurichess had already converted
  # to git, so the canonical repository survived at the same URL.
  src = fetchgit {
    url = "https://bitbucket.org/zurichess/zurichess.git";
    rev = "ee20f164ad4adff42cfc32fc96cc927f1cd4a41e";
    hash = "sha256-cCwvZiJ7ZYbXha76kyeC0JAqrj6qfhSMdhKPIS6Km+w=";
  };

  vendorHash = null;

  # Pure Go; disable cgo for the Windows cross (buildGoModule defaults it on and
  # then fails without a wired mingw C toolchain).
  env.CGO_ENABLED = if stdenv.hostPlatform.isWindows then "0" else "1";

  subPackages = [ "zurichess" ];

  postPatch = ''
    mkdir -p vendor/bitbucket.org/zurichess
    cp -r ${board} vendor/bitbucket.org/zurichess/board
    chmod -R u+w vendor
    cat > vendor/modules.txt <<'EOF'
    # bitbucket.org/zurichess/board v1.0.0
    ## explicit
    bitbucket.org/zurichess/board
    EOF
  '';

  # engine/asm_amd64.s has no aarch64 counterpart; engine/asm.go supplies a
  # no-op prefetch() under `// +build !amd64`, so non-x86 builds are clean.
  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    out_txt=$(printf 'uci\nquit\n' | $emu "$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok' to a uci handshake" >&2
      echo "--- engine output ---" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "ok: ${pname} speaks UCI"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Zurichess, Alexandru Mosoi's UCI chess engine and chess library written in Go";
    homepage = "https://bitbucket.org/zurichess/zurichess";
    # LICENSE in the repository root is the three-clause BSD text,
    # "Copyright (c) 2014-2015, The Zurichess Authors".
    license = licenses.bsd3;
    mainProgram = pname;
    platforms = platforms.unix ++ platforms.windows;
    maintainers = [ ];
  };
}
