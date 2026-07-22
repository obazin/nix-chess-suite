{ lib, stdenv, buildPackages, mkEngine, fetchFromGitHub }:

# Xiphos is a plain C engine with a small hand-written Makefile at the repo
# root, so mkEngine applies. It is Milos Tatarevic's engine, DISTINCT from every
# other lineage here. Despite its TCEC-era reputation, Xiphos never adopted
# NNUE: the evaluation is classical (src/eval.c, src/pawn_eval.c) and there is
# no net file in the tree, on the v0.6 tag or on master, so nothing is fetched
# or embedded and it searches immediately.

mkEngine rec {
  pname = "xiphos";
  version = "0.6";

  # v0.6 is the last release tag. master carries only a couple of post-release
  # commits and the same Makefile/eval, so the tagged release is the cleaner
  # provenance.
  src = fetchFromGitHub {
    owner = "milostatarevic";
    repo = "xiphos";
    rev = "v${version}";
    hash = "sha256-c470oGkWGj12cjYJeZnx0K0Pe7cHsyCawRzMtQvMKaU=";
  };

  # The Makefile offers three targets and NO portable default: `sse` (-msse),
  # `bmi2` (-mbmi2 + BMI2 pext), both x86-only, and `nopopcnt`. Only `nopopcnt`
  # is architecture-neutral — it defines _NOPOPCNT, which selects the C fallbacks
  # for every x86 asm helper in the source:
  #   * _bsf   -> __builtin_ctzll   (else `bsfq` inline asm)
  #   * _popcnt-> a lookup table     (else `popcntq` inline asm)
  #   * bishop/rook attacks -> magic multiply (else the BMI2 `pextq` path)
  #   * position.h drops its <xmmintrin.h> prefetch include
  # so it is the only target that compiles on aarch64. It builds and runs on
  # x86_64 too (just without hardware popcnt), which keeps a single reproducible
  # target across all platforms; the marginal x86 speed loss is acceptable for a
  # ~2000-era classical engine used for sparring.
  makeTarget = "nopopcnt";

  # Xiphos declares globals (search_status, shared_z_keys, ...) in headers as
  # bare tentative definitions. Since GCC 10 / modern clang default to
  # -fno-common, every TU that includes the header emits its own definition and
  # the link fails with "duplicate symbol". Upstream was written against the old
  # -fcommon default; restore it. (This is the whole build's C flag channel, so
  # it also reaches the fathom prober compiled in the same invocation.)
  env.NIX_CFLAGS_COMPILE = "-fcommon";

  # uci.c calls a printf wrapper as `_p(pv_string)` with a non-literal format.
  # nixpkgs' stdenv turns on `-Werror=format-security` by default (the "format"
  # hardening flag), which upstream's own -Wall build never had, so this warns
  # into a hard error. The wrapper only ever prints trusted engine output;
  # disable the format hardening rather than patch a benign upstream idiom.
  hardeningDisable = [ "format" ];

  # The recipe writes `$(TARGET)-nopopcnt`, i.e. `xiphos-nopopcnt`. mkEngine
  # installs that and symlinks `bin/xiphos` -> it, so the smoke test (which uses
  # pname) and `nix run` both resolve.
  binaries = [ "xiphos-nopopcnt" ];

  # No -march/-msse survives in the nopopcnt recipe, so stripArchFlags has
  # nothing to do here, but leaving it on is harmless.

  # mkEngine's default check is handshake-only. Xiphos is classical, not NNUE,
  # but proving it actually searches and returns a move is a stronger guarantee.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/xiphos${stdenv.hostPlatform.extensions.executable}"

    out_txt=$(printf 'uci\nquit\n' | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: xiphos did not answer 'uciok' to a uci handshake" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "ok: xiphos speaks UCI"

    search_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 12\n'; \
      sleep 3; printf 'quit\n'; } | $emu "$bin" | tr -d '\r')
    echo "$search_txt" | grep -q '^bestmove ' || {
      echo "FAIL: xiphos returned no bestmove from 'go depth 12'" >&2
      echo "$search_txt" >&2
      exit 1
    }
    echo "ok: xiphos searches and returns a bestmove"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Xiphos, Milos Tatarevic's classical-evaluation UCI engine in C";
    homepage = "https://github.com/milostatarevic/xiphos";
    # Verified from primary evidence: LICENSE.md is verbatim GNU GPL-3.0 text,
    # and every source header (e.g. src/main.c) reads "either version 3 of the
    # License, or (at your option) any later version", i.e. GPL-3.0-or-later.
    license = licenses.gpl3Plus;
    maintainers = [ ];
  };
}
