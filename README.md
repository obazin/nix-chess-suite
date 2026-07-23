# nix-chess-suite

Reproducible builds of interesting UCI chess engines, pinned by a Nix flake, for Linux, macOS and Windows.

The engine set is seeded from the [Lucas Chess](https://github.com/lukasmonk/lucaschessR2) collection and the [TCEC](https://tcec-chess.com) rosters, and then broadened for **variety**: **~82 engines** spanning a sparring band around 1800-2400 Elo, a dozen at 3000+, the human-like Maia family, and — deliberately — as many distinct lineages, languages, and eval paradigms as could be built cleanly from source.

**8 languages**: C, C++, Rust, Go, C#, Nim, Zig, D. **Three eval paradigms**: NNUE, classical hand-crafted, and Winter's logistic-regression evaluation. Every engine is built from source with a pinned revision (and, where applicable, a pinned NNUE net), and is smoke-tested in-sandbox — the build sends `uci` and a real `go`, and requires both `uciok` and a `bestmove` back, so an engine that compiles but can't play never ships.

The authoritative engine list is `nix flake show` (or `engines/default.nix`); the tables below are a snapshot. See **[Engines.md](Engines.md)** for the full catalogue — every engine with its approximate Elo, platforms, eval method, and source link.

### Languages

| Language | Engines |
|---|---|
| C / C++ | Stockfish, Berserk, Stormphrax*, Caissa, Clover, Seer, Alexandria, PlentyChess, RubiChess, Arasan, Texel, Vajolet2, Winter, Marvin, Minic, Xiphos, Demolito, Senpai, Weiss, Loki, Napoleon, Laser, Wyldchess, Bit-Genie, Willow, Deepov, Maxima2, EXchess, Sayuri, Vice, Wukong, Mister Queen, Fruit, GambitFruit, Toga II, DeepToga, Glaurung, Cheng4, CT800, Stash, Cinnamon, Pulse, Shallow Blue, Rodent IV, Discocheck, Tucano, Jazz, Sjaak II, Gull†, Obsidian†, Igel† |
| Rust | Reckless, Viridithas, Carp, Akimbo, BlackMarlin, Svart, Velvet, Wahoo, Rustic, FabChess |
| Go | Counter, Zurichess, Blunder, Combusken |
| C# | Leorik, Lynx (native self-contained, no .NET runtime in the closure) |
| Nim | Heimdall |
| Zig | Avalanche |
| D | Amoeba, Dumb |

\* Stormphrax is C++. † x86-only, platform-gated (see below). Plus **Lc0** (+ a distilled CPU net) and **Maia 1100–1900** as nine human-like engines.

## Installing

### With Nix (macOS / Linux)

Run one engine without installing anything:

```sh
nix run github:obazin/nix-chess-suite#stockfish
```

Install **one** engine into your profile (puts it on `PATH`):

```sh
nix profile install github:obazin/nix-chess-suite#maia-1500
```

Install **every** engine at once — the `all` bundle (== the default) merges all
engines into one `bin/`, so `stockfish`, `fruit`, `lc0`, `maia-1500`, … all land
on `PATH`:

```sh
nix profile install github:obazin/nix-chess-suite       # or: #all
```

List what's available for your system:

```sh
nix flake show github:obazin/nix-chess-suite
```

**You don't compile anything.** The flake advertises its binary cache (a
Cloudflare R2 bucket at `pub-…​.r2.dev`) via `nixConfig`, so the commands above
download the prebuilt, CI-pushed binaries. Nix asks once to trust the cache
(answer `y`); to pre-trust it, add to your `nix.conf`:

```
extra-substituters = https://pub-428250a0977d4667937b8ce7e16887ce.r2.dev
extra-trusted-public-keys = nix-chess-suite-1:5uNzouWBsIpF0iwdnTgQj2A8ZSdvFFLfV5kkiapqW9U=
```

Without the cache, Nix would build all ~79 engines from source locally —
correct, but slow.

### Native (maximum-strength) variants

The cached binaries are **portable**: built to a conservative baseline
(AVX2/BMI2 on x86-64, NEON on ARM) so one binary runs on any CPU of that
architecture. That costs a few percent versus a build tuned to *your* CPU.

For the strong (3000+) tier, opt-in **`-native`** variants are built with
`-march=native` (Rust engines with `target-cpu=native`), so they use everything
your CPU has — AVX-512, specific tuning, etc. Because a native binary is only
valid on the CPU that built it, these are **always built locally and never
cached** (not pulled from or pushed to the shared cache):

```sh
# one native engine (compiles on your machine, ~a few minutes)
nix profile install github:obazin/nix-chess-suite#stockfish-native

# the whole strong tier, native
nix profile install github:obazin/nix-chess-suite#native
```

Available: `stockfish-native`, `berserk-native`, `caissa-native`,
`clover-native`, `seer-native`, `stormphrax-native`, `alexandria-native`,
`plentychess-native`, `rubichess-native`, `obsidian-native` (x86), and the Rust
`viridithas-native`, `reckless-native`. Use these for serious analysis or rating
runs; the portable cached builds are the right default for casual/sparring use.

### In your own flake / NixOS / home-manager

The flake ships `overlays.default`, which adds a `chessEngines` attrset:

```nix
{
  inputs.chess.url = "github:obazin/nix-chess-suite";
  # ...
  # NixOS or home-manager module:
  nixpkgs.overlays = [ inputs.chess.overlays.default ];
  environment.systemPackages = [
    pkgs.chessEngines.stockfish
    pkgs.chessEngines.arasan
  ];
  # or grab everything:
  # environment.systemPackages = [ inputs.chess.packages.${pkgs.system}.all ];
}
```

Then point your GUI (cutechess, en-croissant, BanksiaGUI, Arena, …) at the
installed binaries, e.g. `~/.nix-profile/bin/stockfish`.

### Without Nix

Nix-built Linux/macOS binaries link against libraries in `/nix/store`, so you
can't just copy one to a non-Nix machine and run it. What works, per platform:

- **Linux, no Nix** — run `nix bundle` *on a Linux machine* to turn any engine
  into a self-contained, portable executable (an AppImage-style single file)
  that then runs anywhere without Nix:

  ```sh
  nix bundle github:obazin/nix-chess-suite#stockfish   # -> ./stockfish (portable)
  ```

- **Windows** — the `.exe`s are mingw cross-builds that link against Windows
  DLLs, so they're genuinely portable. They're attached to each
  [release](../../releases) for the engines that support Windows (see the
  platform table); keep the accompanying `lib*.dll`s next to them.

- **macOS, no Nix** — macOS binaries embed `/nix/store` dylib paths and aren't
  easily made portable; the realistic path is to install Nix (one command) and
  use `nix profile install` above.

For anyone who can install Nix, that's by far the simplest route on both Linux
and macOS: every engine, reproducibly, with nothing dumped into the system.

## Platform support

| Platform | How it is built | Status |
|---|---|---|
| `aarch64-darwin` | Nix flake | ✅ fully verified — every engine builds and passes UCI |
| `x86_64-linux` | Nix flake | ✅ fully verified |
| `aarch64-linux` | Nix flake | ✅ fully verified |
| `x86_64-windows` | Nix flake, cross-compiled (`pkgsCross` → mingw) | ✅ 46 engines cross-compile and link (non-blocking job; no in-sandbox UCI check — that would need Wine) |
| `x86_64-darwin` | — | **not supported** (nixpkgs dropped it) |

All three Nix-managed platforms build every applicable engine in CI and pass the in-sandbox UCI check. Coverage is honest rather than aspirational: an engine that genuinely can't build on a platform has its `meta.platforms` narrowed to exclude it — the x86-only engines (Obsidian, Igel) are excluded on aarch64, and Gull (fixed-address linking no toolchain here accepts) is declared for Windows only. The Windows cross job now links 46 engines; it stays non-blocking because the `.exe`s can't run a UCI check in-sandbox without Wine.

Two deliberate decisions here. **Windows** is produced by cross-compiling the same engine derivations to mingw (UCRT) with `pkgsCross`, from the `x86_64-linux` runner — reusing every patch, net pin and flag rather than reimplementing them in a native MSYS2 build script. Not every engine survives the cross (some assume POSIX APIs, some are Go+cgo / Zig / D that don't cross cleanly); those have Windows dropped from their `meta.platforms` and are honestly excluded. **Intel Mac** is unsupported because nixpkgs [removed `x86_64-darwin` from `lib.systems.doubles`](https://github.com/NixOS/nixpkgs/commit/fdb82060) in July 2026; supporting it would mean pinning a stale nixpkgs for every engine.

## Engine tiers

### `strong` — 3000+ Elo

Actively developed, NNUE-based, TCEC Premier Division regulars. CI tracks these nightly.

| Engine | Elo (CCRL 40/15) | License | Net handling |
|---|---|---|---|
| Stockfish | ~3650 | GPL-3.0 | pinned `fetchurl`, embedded |
| Lc0 | TCEC #2 | GPL-3.0 | weights are a separate runtime derivation |
| Obsidian | 3618 | GPL-3.0 | pinned `fetchurl` |
| Berserk | 3616 | GPL-3.0 | pinned `fetchurl` |
| PlentyChess | 3611 | GPL-3.0 | pinned + build-native preprocessor |
| Caissa | 3610 | MIT | pinned `fetchurl` |
| RubiChess | 3602 | GPL-3.0 | pinned `fetchurl` |
| Viridithas | 3602 | AGPL-3.0 | pinned; disable PGO |
| Alexandria | 3602 | GPL-3.0 | pinned + preprocessor |
| Clover | 3597 | GPL-3.0 | **net committed in-repo** |
| Seer | 3585 | GPL-3.0 | pinned `fetchurl` |
| Stormphrax | 3535 | GPL-3.0 | pinned `fetchurl` |
| Reckless | 3417+ | AGPL-3.0 | pinned; S29 Superfinalist, rating is stale |

Eleven of these download an NNUE net at build time, which the Nix sandbox forbids. Each net is pinned as its own `fetchurl` with an SRI hash and passed through `EVALFILE=`, following the pattern nixpkgs already uses for `stockfish`.

### `classic` — the 1800-2400 sparring band

Mostly frozen upstream; several have not seen a commit in fifteen years. Built from pinned tags. CI does not chase updates here — it runs a scheduled build against `nixpkgs-unstable` to catch *toolchain drift*, which is the real maintenance burden for 2000s-era C.

Dozens of engines across ~1800-3000 Elo, from actively-maintained (Arasan, Texel, Marvin, Minic) to long-frozen 2000s-era C (Fruit 2.1, Glaurung, Vice). A representative slice — see `nix flake show` for the full list:

| Engine | Approx Elo | Language | Note |
|---|---|---|---|
| Arasan 25.4 | ~3450 | C++ | Jon Dart's own 30-year MIT codebase |
| Texel | ~3200 | C++ | grew from CuckooChess; distinct lineage |
| Winter | ~3100 | C++ | logistic-regression eval (a third paradigm) |
| Rodent IV | ~2900 | C++ | personality files make it a versatile sparring set |
| Glaurung 2.2 | ~2790 | C++ | direct ancestor of Stockfish |
| Cheng 4.48 | ~2750 | C++ | Zlib; unity build, NNUE embedded |
| Sayuri | ~2250 | C++ | embeds a "Sayulisp" Scheme interpreter |
| Fruit 2.1 | ~2200 | C++ | the GPL ancestor of Toga; pin must never move |
| Vice | ~1900 | C | the didactic "Programming a Chess Engine in C" engine |
| Shallow Blue | ~1900 | C++ | clean, small |
| Rustic | ~1800 | Rust | didactic; from Codeberg |
| Wukong / Mister Queen | didactic | C | minimalist reference engines |

### `humanlike` — Lc0 + Maia

The 1800-2400 band is thinly populated in modern open-source engines: almost everything actively maintained is 2800+, and the genuinely weak engines are abandoned. [Maia](https://maiachess.com) nets are a better answer for sparring, because they are trained to play like humans *at a target rating* rather than to play strong moves with artificial blunders injected, which is what `UCI_LimitStrength` gives you.

`maia-1100` through `maia-1900` are packaged as separate engine outputs wrapping a shared `lc0`.

## Licensing policy

This repository's own packaging — the Nix expressions, CI workflows, and documentation — is released under the [MIT License](LICENSE). That licence does **not** relicense the engines: each engine's source is fetched from its own upstream at build time and remains under that upstream's licence (GPL-2.0/3.0, AGPL-3.0, MIT, BSD, Zlib, Apache-2.0, …), with those obligations unaffected. See each `engines/<name>.nix` for the per-engine licence.

Only engines with a **verified redistributable licence** are included. Every entry was checked against primary evidence — an upstream `LICENSE` file or an explicit statement by the author — not against secondary sources like the Chessprogramming wiki.

Notable exclusions are documented in [`docs/excluded.md`](docs/excluded.md). In brief: **Hiarcs** and **Komodo** are commercial; **Critter**, **Roce**, **Bikjump** and **Saruman** are binary-only freeware with no source release; **Daydreamer**, **Integral** and **Motor** are publicly readable on GitHub but carry *no licence grant at all*, which is not the same as open source; **Nalwald** is Creative-Commons non-commercial (not free software); and **Ethereal** is GPLv3 in source but its NNUE net is sold separately, so a source build cannot reach anything near its rated strength.

Two further scope rules. **Native binaries only**: engines that need a runtime interpreter/VM at execution are excluded, which rules out the JVM engines (CuckooChess, Carballo, Bagatur, Pirarucu) and Python Sunfish. C# qualifies because .NET publishes a self-contained single-file binary with the runtime bundled in — Leorik and Lynx ship with no .NET in the closure. **x86-only engines** with no NEON or scalar fallback (**Obsidian**, **Gull**, **Igel**) are packaged but platform-gated to `x86_64-linux`/`x86_64-windows`; they are skipped on aarch64 and must be build-verified on an x86 runner.

## Repository layout

```
flake.nix              # outputs, platform matrix
lib/mkEngine.nix       # shared builder: arch-flag stripping, UCI smoke test, install
engines/default.nix    # the registry
engines/*.nix          # one file per engine
docs/excluded.md       # engines considered and rejected, with reasons
```

`mkEngine` exists because these engines fail in the same handful of ways: hardcoded `-march=`/`-msse3`/`-mpopcnt` that break on aarch64, hardcoded `CC=gcc` that ignores the Nix toolchain, no `install` target, and nets fetched over the network. Centralising the fixes keeps each engine file down to a source pin and a licence.

Every engine is smoke-tested in-sandbox: the build sends `uci` and requires `uciok` back. This catches the common failure mode where an engine compiles cleanly and then dies instantly on a missing net or data file.

## Contributing an engine

1. Add `engines/<name>.nix` calling `mkEngine`.
2. Register it in `engines/default.nix` under the right tier.
3. Record the licence with primary evidence in the `meta`.
4. `nix build .#<name>` must pass, smoke test included.
