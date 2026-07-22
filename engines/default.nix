{ pkgs, mkEngine ? pkgs.callPackage ../lib/mkEngine.nix { } }:

# The engine registry.
#
# Tiering (see README for the full policy):
#   strong     - 3000+ Elo, tracked nightly by CI, mostly NNUE
#   classic    - the 1800-2400 sparring band; frozen upstream, built from
#                pinned tags, checked periodically against toolchain drift
#   humanlike  - lc0 + Maia nets, rating-targeted human-like play
#
# Only engines with a verified redistributable licence appear here. See
# docs/excluded.md for what was rejected and why.
#
# `callPackage` supplies mkEngine only to engines that declare it as an
# argument, so Makefile engines and buildGoModule/CMake engines coexist
# without the latter needing to accept an ignored `mkEngine` param.

let
  scope = pkgs.extend (_: _: { inherit mkEngine; });
  callEngine = path: scope.callPackage path { };

  # maia.nix returns an attrset of engines; callPackage tacks `override`/
  # `overrideDerivation` onto it, which must not leak into the registry.
  maia = builtins.removeAttrs (callEngine ./maia.nix) [ "override" "overrideDerivation" ];
  lc0 = builtins.removeAttrs (callEngine ./lc0.nix) [ "override" "overrideDerivation" ];
in
maia // lc0 // {
  ## classic --------------------------------------------------------------
  fruit = callEngine ./fruit.nix;
  gambitfruit = callEngine ./gambitfruit.nix;
  togaii = callEngine ./togaii.nix;
  glaurung = callEngine ./glaurung.nix;
  deeptoga = callEngine ./deeptoga.nix;
  cheng4 = callEngine ./cheng4.nix;
  zurichess = callEngine ./zurichess.nix;
  ct800 = callEngine ./ct800.nix;
  stash = callEngine ./stash.nix;
  pulse = callEngine ./pulse.nix;
  shallow-blue = callEngine ./shallow-blue.nix;
  cinnamon = callEngine ./cinnamon.nix;
  counter = callEngine ./counter.nix;
  rodent-iv = callEngine ./rodent-iv.nix;
  discocheck = callEngine ./discocheck.nix;
  tucano = callEngine ./tucano.nix;
  jazz = callEngine ./jazz.nix;
  sjaak2 = callEngine ./sjaak2.nix;

  ## strong ---------------------------------------------------------------
  stockfish = callEngine ./stockfish.nix;
  berserk = callEngine ./berserk.nix;
  stormphrax = callEngine ./stormphrax.nix;
  # Obsidian has no NEON/scalar NNUE path — x86-only. Platform-gated in its
  # own meta; unverifiable on aarch64, must be checked on an x86_64 runner.
  obsidian = callEngine ./obsidian.nix;
  reckless = callEngine ./reckless.nix;
  viridithas = callEngine ./viridithas.nix;
  plentychess = callEngine ./plentychess.nix;
  rubichess = callEngine ./rubichess.nix;
  caissa = callEngine ./caissa.nix;
  clover = callEngine ./clover.nix;
  seer = callEngine ./seer.nix;
  alexandria = callEngine ./alexandria.nix;

  ## variety — distinct lineages (see docs, prioritised over count) --------
  arasan = callEngine ./arasan.nix;
  senpai = callEngine ./senpai.nix;
  weiss = callEngine ./weiss.nix;
  # Gull: x86-only inline asm, no NEON path. Platform-gated; verify on x86.
  gull = callEngine ./gull.nix;
  # C#, self-contained single-file publish — native binary, no .NET runtime dep.
  leorik = callEngine ./leorik.nix;
  lynx = callEngine ./lynx.nix;
  # Rust
  carp = callEngine ./carp.nix;
  akimbo = callEngine ./akimbo.nix;
  blackmarlin = callEngine ./blackmarlin.nix;
  svart = callEngine ./svart.nix;
  # distinct strong C++ (Winter uses a logistic-regression eval, not NNUE/HCE)
  marvin = callEngine ./marvin.nix;
  texel = callEngine ./texel.nix;
  vajolet2 = callEngine ./vajolet2.nix;
  winter = callEngine ./winter.nix;
  demolito = callEngine ./demolito.nix;
  xiphos = callEngine ./xiphos.nix;
  blunder = callEngine ./blunder.nix;
  minic = callEngine ./minic.nix;
  # Igel: x86-only (unconditional immintrin.h). Platform-gated; verify on x86.
  igel = callEngine ./igel.nix;

  ## variety — exotic languages -------------------------------------------
  amoeba = callEngine ./amoeba.nix;    # D
  dumb = callEngine ./dumb.nix;        # D
  avalanche = callEngine ./avalanche.nix;  # Zig
  heimdall = callEngine ./heimdall.nix;    # Nim

  ## variety — more Rust --------------------------------------------------
  velvet = callEngine ./velvet.nix;
  wahoo = callEngine ./wahoo.nix;
  rustic = callEngine ./rustic.nix;
  fabchess = callEngine ./fabchess.nix;

  ## variety — Go, didactic, and more distinct C/C++ ----------------------
  combusken = callEngine ./combusken.nix;   # Go
  sayuri = callEngine ./sayuri.nix;         # embeds a Scheme interpreter
  vice = callEngine ./vice.nix;             # the didactic "Programming a Chess Engine" engine
  wukong = callEngine ./wukong.nix;
  mister-queen = callEngine ./mister-queen.nix;
  loki = callEngine ./loki.nix;
  # Napoleon v1.5.0 is the last classical release; v1.6+ needs CUDA/ONNX. Do not bump.
  napoleon = callEngine ./napoleon.nix;
  laser = callEngine ./laser.nix;
  wyldchess = callEngine ./wyldchess.nix;
  bit-genie = callEngine ./bit-genie.nix;
  willow = callEngine ./willow.nix;
  deepov = callEngine ./deepov.nix;
  maxima2 = callEngine ./maxima2.nix;
  # EXchess: UCI is a 2026 addition upstream; shipped with the classic
  # (NNUE-off) eval. See the file header for provenance.
  exchess = callEngine ./exchess.nix;
}
