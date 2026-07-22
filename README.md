# nix-chess-suite

Reproducible builds of interesting UCI chess engines, pinned by a Nix flake, for Linux, macOS and Windows.

The engine set is seeded from the [Lucas Chess](https://github.com/lukasmonk/lucaschessR2) collection and the [TCEC](https://tcec-chess.com) rosters, and then broadened for **variety**: **~82 engines** spanning a sparring band around 1800-2400 Elo, a dozen at 3000+, the human-like Maia family, and — deliberately — as many distinct lineages, languages, and eval paradigms as could be built cleanly from source.

**8 languages**: C, C++, Rust, Go, C#, Nim, Zig, D. **Three eval paradigms**: NNUE, classical hand-crafted, and Winter's logistic-regression evaluation. Every engine is built from source with a pinned revision (and, where applicable, a pinned NNUE net), and is smoke-tested in-sandbox — the build sends `uci` and a real `go`, and requires both `uciok` and a `bestmove` back, so an engine that compiles but can't play never ships.

The authoritative engine list is `nix flake show` (or `engines/default.nix`); the tables below are a snapshot.

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

## Quick start

```sh
nix run github:obazin/nix-chess-suite#fruit      # run one engine
nix build github:obazin/nix-chess-suite          # build everything for this system
nix flake show github:obazin/nix-chess-suite     # list available engines
```

Prebuilt binaries for all platforms are attached to each [release](../../releases).

## Platform support

| Platform | How it is built | Status |
|---|---|---|
| `aarch64-darwin` | Nix flake | ✅ fully verified — every engine builds and passes UCI |
| `x86_64-linux` | Nix flake | 🚧 in progress — most engines build; per-engine gaps being closed |
| `aarch64-linux` | Nix flake | 🚧 in progress |
| `x86_64-windows` | GitHub Actions, MSYS2/mingw | 🚧 in progress — not Nix-managed |
| `x86_64-darwin` | — | **not supported** (nixpkgs dropped it) |

The engine set was developed and verified on `aarch64-darwin`, which is the blocking CI platform. Linux and Windows are being brought up per-engine: an engine that can't build on a platform has its `meta.platforms` narrowed to exclude it (as Obsidian, Gull and Igel already are for being x86-only), so coverage is honest rather than aspirational. Their CI jobs are non-blocking until complete.

Two deliberate decisions here. Windows is built on native runners rather than `pkgsCross.mingw-ucrt-x86_64` because a meaningful fraction of these hand-rolled Makefiles do not survive cross-compilation, and debugging 40 of them individually is not a good use of anyone's time. Intel Mac is unsupported because nixpkgs [removed `x86_64-darwin` from `lib.systems.doubles`](https://github.com/NixOS/nixpkgs/commit/fdb82060) in July 2026; supporting it would mean pinning a stale nixpkgs for every engine.

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
