# `mkEngine` is accepted and ignored: engines/default.nix and test-engine.nix
# pass it to every engine file unconditionally. Heimdall is written in Nim, so
# mkEngine (stdenv.mkDerivation + Makefile fixups for C engines) does not apply.
# This is a plain stdenv.mkDerivation driving the Nim compiler. The meta fields
# and the UCI smoke test below mirror lib/mkEngine.nix so the engine is held to
# the same standard as the rest of the collection.
{ lib, stdenv, buildPackages, fetchFromGitHub, fetchurl, nim, zlib, clang, mkEngine ? null }:

# Heimdall is nocturn9x's NNUE UCI engine written in Nim. Two things make it the
# awkward one to package hermetically, and both are handled here without any
# network access at build time:
#
#  1. Nim dependencies. heimdall.nimble pulls six libraries off the internet via
#     `nimble install -d`. We bypass nimble entirely (as the D/Go/Zig engines in
#     this collection bypass their build tools) and instead fetch each dependency
#     as a pinned source and hand Nim their module paths through a generated
#     `src/heimdall.nim.cfg`. All six are dependency-free, so there is no
#     transitive tree to chase. nimsimd is NOT among them: it is only imported
#     under `when defined(simd)` (src/heimdall/util/simd.nim), and this is a
#     no-SIMD build, so it is correctly excluded.
#
#  2. The NNUE net. It is NOT in the repo: the `networks` git submodule points at
#     the author's self-hosted Gitea (git.nocturn9x.space) and the weights live
#     there under Git LFS. The submodule is pinned at commit 77efb72, and Gitea's
#     LFS `media` endpoint serves the raw 36 MB net over plain HTTPS at a
#     commit-addressed URL, so it can be pinned with fetchurl. The Git LFS object
#     id is by spec the SHA-256 of the content, and the fetchurl hash below is
#     exactly that id, so the pin is content-verified end to end. We pass it to
#     Nim as an absolute path via EVALFILE; nnue.nim `staticRead`s it at compile
#     time (-d:evalFile), so the net is baked into the binary and there is no
#     separate runtime file.
#
# The upstream Makefile's build targets are all x86 (native/modern/zen2 add
# -march=haswell/znver2/..., and even `legacy` pins -march=core2) and its base
# CFLAGS carry `-static`, which does not link on Darwin. We drive the `legacy`
# (no-SIMD) target with SKIP_DEPS=1 but override CFLAGS_LEGACY and LFLAGS to drop
# the x86 arch flags, the static link, and the LTO/lld linker wiring, leaving a
# clean portable aarch64 build. Optimisation still comes from Nim's `-d:danger`
# (the Makefile's default, which implies --opt:speed) plus C-level -O2.
let
  # heimdall.nimble requires. All six are leaf packages (no `requires` of their
  # own beyond nim itself), so pinning the sources is enough.
  jsony = fetchFromGitHub {
    owner = "treeform";
    repo = "jsony";
    rev = "1.1.5";
    hash = "sha256-alkqZ3Q8+BzDDZo2hR3KRfzGrGhHQ/gDhxVD2TWOQJw=";
  };
  nint128 = fetchFromGitHub {
    owner = "rockcavera";
    repo = "nim-nint128";
    rev = "v0.3.3";
    hash = "sha256-YZgiOqmIt0XYsyhAfYAOJeN5CIAY0JyhYr9VXw/0+0s=";
  };
  struct = fetchFromGitHub {
    owner = "OpenSystemsLab";
    repo = "struct.nim";
    rev = "v0.2.3";
    hash = "sha256-aHrfkpaK0iB8AQ+bIofuclC8QGutSIZrS3kFzz21JoU=";
  };
  pathX = fetchFromGitHub {
    owner = "demotomohiro";
    repo = "pathX";
    # No tags upstream; the .nimble reads version 0.1.0, which satisfies the
    # `pathX == 0.1` requirement. Pinned to the current HEAD commit.
    rev = "fda0dfe4dda7c6e7284dbd7ec93c6fc50a3e0e46";
    hash = "sha256-SVZC+FWjDTeJCt7BwbQCNsaVK3B1u4XC18jMfnRQjgI=";
  };
  noise = fetchFromGitHub {
    owner = "jangko";
    repo = "nim-noise";
    rev = "v0.1.10";
    hash = "sha256-YXRG53mJo5B9OC0Ud1XD/knyfHxwiKzzn0DeGKdGZeY=";
  };
  illwill = fetchFromGitHub {
    owner = "johnnovak";
    repo = "illwill";
    rev = "v0.4.1";
    hash = "sha256-U5P0hIWMPjDev4Ml0eqfrCjzSr2ufhno04YrLX1hMUI=";
  };

  # NNUE net (gramr.bin), pinned at the `networks` submodule commit. The hash is
  # the Git LFS object id (SHA-256 of the content) taken from the LFS pointer.
  net = fetchurl {
    name = "gramr.bin";
    url = "https://git.nocturn9x.space/heimdall-engine/networks/media/commit/77efb7273d5758a725ea1cf2716b610cdddc757b/files/gramr.bin";
    hash = "sha256-zD1l2DOD7VOEihb9xxduTa/lKMhfJyKuWB8XjG6DY4E=";
  };
in
stdenv.mkDerivation rec {
  pname = "heimdall";
  version = "1.5.0";

  src = fetchFromGitHub {
    owner = "nocturn9x";
    repo = "heimdall";
    rev = "d8ec13e0496a814025d9c299bf34dc393160f81e";
    hash = "sha256-JdYOjCJWl59rroC+oeu8a3y+5jcEAL9zedP3ffxCv/Q=";
  };

  # The Makefile invokes Nim with CC=clang (nim then spawns `clang` for its C
  # backend). Darwin's stdenv cc *is* clang, so it's already on PATH there; on
  # Linux (gcc stdenv) clang is absent, so add it explicitly.
  nativeBuildInputs = [ nim ] ++ lib.optional stdenv.hostPlatform.isLinux clang;
  # zlib: the terminal-UI module (src/heimdall/tui/util/kitty.nim) FFIs into
  # zlib for the kitty image protocol (`{.passl: "-lz".}`, `#include <zlib.h>`).
  # The stdenv cc wrapper supplies the header and link path from this input.
  buildInputs = [ zlib ];

  postPatch = ''
    # Point Nim at the vendored dependency sources instead of running
    # `nimble install -d`. Nim reads `<mainmodule>.nim.cfg` from the directory
    # of the compiled file (src/heimdall.nim), so these --path entries are
    # picked up on top of the Makefile's own --path:src.
    cat > src/heimdall.nim.cfg <<EOF
    --path:"${jsony}/src"
    --path:"${nint128}/src"
    --path:"${struct}/src"
    --path:"${pathX}/src"
    --path:"${noise}"
    --path:"${illwill}"
    EOF

    # --- Nim 2.2.10 compatibility (upstream pins nim == 2.2.6) ---
    # (1) File and Rank are `distinct range[0'u8..7'u8]`. The stdlib `..`
    #     iterator ends its enum branch with `inc(res)` on the last value, which
    #     overflows the range and aborts the compile-time VM ("value out of
    #     range") while the magic-bitboard tables are generated at compile time.
    #     (Square is `range[0..64]` with high 63, so it does not overflow; only
    #     File/Rank do.) Iterate an explicit array literal instead: it loops by
    #     int index and never increments past the range. Nim 2.2.6 structured
    #     the `..` iterator differently and did not hit this. The `notin
    #     File.all()`/`Rank.all()` uses elsewhere go through `contains`, not the
    #     iterator, so they are left untouched.
    substituteInPlace src/heimdall/util/magics.nim \
      --replace-fail 'for rank in Rank.all():' 'for rank in [Rank(0),Rank(1),Rank(2),Rank(3),Rank(4),Rank(5),Rank(6),Rank(7)]:' \
      --replace-fail 'for file in File.all():' 'for file in [pieces.File(0),pieces.File(1),pieces.File(2),pieces.File(3),pieces.File(4),pieces.File(5),pieces.File(6),pieces.File(7)]:'

    # (2) A `let` bound inside an `if (let x = ...; x) != y:` statement
    #     expression no longer leaks into the branch body under Nim 2.2.10, so
    #     the following `ray = shifted` fails with "undeclared identifier".
    #     Hoist the binding to a plain statement; semantics are unchanged.
    substituteInPlace src/heimdall/util/magics.nim \
      --replace-fail $'            if (let shifted = ray.tryOffset(file, rank); shifted) != nullSquare():\n                ray = shifted' $'            let shifted = ray.tryOffset(file, rank)\n            if shifted != nullSquare():\n                ray = shifted'

    # --- Portable, hermetic build wiring ---
    # The Makefile's build targets are all x86 (legacy pins -march=core2), its
    # base CFLAGS carry `-static` (unlinkable on Darwin), and it links through
    # `-flto -fuse-ld=lld`. Drop the two Nim flags that inject all of that:
    # `--passC:"$(CFLAGS_LEGACY)"` (x86 arch + static) and `--passL:"$(LFLAGS)"`
    # (LTO + lld). Nim's own `-d:danger` (the Makefile default) already compiles
    # the C with --opt:speed, and the stdenv linker handles the rest, so the
    # result is a clean portable aarch64 build. (Removing --passC also sidesteps
    # a quirk where this Nim leaks the raw `--passC:...` token into the final
    # link command, which clang then rejects.)
    substituteInPlace Makefile \
      --replace-fail ' --passL:"$(LFLAGS)"' "" \
      --replace-fail ' --passC:"$(CFLAGS_LEGACY)"' ""

    # NUMA autodetection reads /sys/devices/system/{cpu,node}/... at startup.
    # readTrimmed catches OSError, but Nim's readFile raises IOError (not an
    # OSError subtype) when the path is absent — as it is in the build sandbox
    # (and any /sys-less environment) — so the engine aborts on the first `go`.
    # Broaden the catch to CatchableError so the missing file yields `none` and
    # NUMA detection degrades gracefully.
    substituteInPlace src/heimdall/util/numa.nim \
      --replace-fail 'except OSError:' 'except CatchableError:'
  '';

  # Nim needs a writable HOME and cache in the sandbox. SKIP_DEPS=1 stops the
  # Makefile from invoking nimble and the git-submodule/LFS `net` target; we
  # supply both ourselves (see postPatch and the pinned `net`). The x86/static/
  # LTO flags are already stripped from the Makefile in postPatch. EVALFILE is
  # the absolute path to the pinned net so nnue.nim's compile-time staticRead
  # resolves unambiguously and bakes the weights into the binary.
  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    make legacy SKIP_DEPS=1 CC=clang EVALFILE="${net}"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/heimdall "$out/bin/heimdall${stdenv.hostPlatform.extensions.executable}"
    runHook postInstall
  '';

  doInstallCheck = stdenv.hostPlatform.emulatorAvailable buildPackages;

  # Same guarantee as mkEngine, plus a real search: handshake to uciok, then
  # require a bestmove from `go depth 8`. Quitting immediately would cancel the
  # search and yield a false failure, so we sleep before sending quit. A net that
  # failed to embed would pass the handshake but crash on `go`, so this also
  # proves the staticRead'd NNUE loaded.
  installCheckPhase = ''
    runHook preInstallCheck
    emu="${stdenv.hostPlatform.emulator buildPackages}"
    bin="$out/bin/${pname}${stdenv.hostPlatform.extensions.executable}"

    out_txt=$( { printf 'uci\nisready\nposition startpos\ngo depth 8\n'; \
      sleep 4; printf 'quit\n'; } | $emu "$bin" | tr -d '\r')
    echo "$out_txt" | grep -q uciok || {
      echo "FAIL: ${pname} did not answer 'uciok' to a uci handshake" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "$out_txt" | grep -q '^bestmove ' || {
      echo "FAIL: ${pname} returned no bestmove from 'go depth 8'" >&2
      echo "$out_txt" >&2
      exit 1
    }
    echo "ok: ${pname} speaks UCI and searches (embedded net loaded)"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Heimdall, nocturn9x's strong NNUE UCI chess engine written in Nim";
    homepage = "https://github.com/nocturn9x/heimdall";
    # LICENSE in the repo root is the verbatim Apache License 2.0. Source headers
    # carry the standard Apache-2.0 SPDX notice.
    # https://github.com/nocturn9x/heimdall/blob/master/LICENSE
    license = licenses.asl20;
    mainProgram = "heimdall";
    # Gated off Windows: Nim's C backend cross to mingw needs a cross clang
    # this toolchain doesn't provide.
    platforms = platforms.unix;
    maintainers = [ ];
  };
}
