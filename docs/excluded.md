# Excluded engines

Engines considered for the collection and rejected, with the reason and the primary evidence. Recorded so the same research is not repeated.

The bar for inclusion is a **verified redistributable licence**, established from an upstream `LICENSE`/`COPYING` file or an explicit statement by the author. Secondary sources — the Chessprogramming wiki in particular — were not treated as sufficient, and in several cases below they were wrong.

## Commercial — redistribution prohibited

| Engine | Evidence |
|---|---|
| Hiarcs | Full EULA from Applied Computer Concepts Ltd. No redistribution rights under any terms. |
| Komodo / Komodo Dragon | Proprietary; terms explicitly ban redistribution. Note `komodochess.com` went offline 2026-07-31. |
| Torch | Chess.com, closed source. |
| Stoofvlees, rofChade, SlowChess, Deep Sjeng, Uralochka, Ginkgo, Fritz, Rebel | Closed-source TCEC participants. |

## Binary-only — no source release

Legal to *use*, but nothing to build, so out of scope for a source-built flake.

| Engine | Evidence |
|---|---|
| Critter 1.6a | Richard Vida never released the C++ source. Note: `rchastain/open-critter` is a **different** GPL-2.0 Object Pascal engine from the pre-0.42 Delphi lineage, not this program. |
| Roce38 | Roman Hartmann (not Waldteufel), who stated directly that the source would most likely not be released. |
| Bikjump | Aart Bik. The shipped `bikjump.txt` describes the licence and confirms he wrote the code himself, but no source was ever distributed. Non-commercial terms in any case. |
| Saruman | Terry Bolt, Darragh Griffin, Conor Griffin per the binary's own UCI `id author`. No homepage, repository or licence statement found. |
| Gaviota | The open MIT code at `michiguel/Gaviota-Tablebases` is the **tablebase prober**, not the engine. The engine was never released. |

## Publicly readable but not licensed

The most easily mistaken category. A public GitHub repository is not a licence: absent a grant, default copyright reserves all rights.

| Engine | Evidence |
|---|---|
| Daydreamer | `github.com/AaronBecker/daydreamer` has no `LICENSE` file. The C source matching the common binary reads `Copyright 2009-2010, all rights reserved`. The Rust 2.0 rewrite claims `Apache-2.0` in `Cargo.toml` metadata only, with no licence text. Would need Becker's permission. |
| Integral | TCEC S28/S29 Premier Division, ~3584 Elo. No `LICENSE` file, no README mention. |
| GreKo | Only `(c) Vladimir Medvedev` headers, no licence text anywhere. |
| Andscacs | `license: null` per GitHub, no headers in source. |

## Licensed, but excluded on other grounds

| Engine | Reason |
|---|---|
| Ethereal | GPL-3.0 source, verbatim and unmodified — it did **not** relicense. But since v13 the trained NNUE weights are withheld and sold separately (~$60). A source build falls back to `USE_NNUE=0` and plays far below its listed ~3600, which would make its presence in the collection misleading. |

## Unresolved

Excluded pending evidence rather than rejected outright.

| Engine | Status |
|---|---|
| Rocinante 2.0 | Antonio Torrecillas released source, but the GPL claim traces only to the Chessprogramming wiki; his release post names no licence and his Google Sites page is now login-walled. Sits squarely in the target Elo band, so worth an email. |
| Pawny 1.2 | Lucas Chess bundles a `gpl.txt`, but no live upstream source URL exists. |
| Toga II | Active at `github.com/Joachim26/TogaII`, but ships no `LICENSE`. GPL applies by derivation from Fruit 2.1; included on that basis and documented here. |
| Cinnamon | Source headers and README say GPLv3+; the `LICENSE` file contains LGPL-3.0 text. Treated as GPLv3+ as the conservative reading. Worth asking the author to resolve. |

## Version pinning notes

**Fruit** — only 2.1 is GPL-2.0-or-later. Versions 2.2 through 2.3.1 are proprietary, and 2.3+ was transferred to a different maintainer under non-GPL terms. This pin must never be bumped. Fruit 2.1 was later assigned to the FSF and became GNU Chess 6; "Fruit Reloaded" is a separate legitimate GPLv3 fork.

**Lucas Chess version drift** — Lucas pins engines well behind upstream (Arasan 22.2 from 2020 against a current 25.4; Stash 29.0 against 37; Tucano 9.00 against 12). Pinning Lucas's exact tags would reproduce its Elo ladder faithfully, but forfeits the ARM build fixes upstream has landed since. This collection tracks upstream instead, because the Lucas Elo numbers are specific to its own ladder anyway. Tucano is the deliberate exception: v9.00 is pinned because it is the last release before NNUE, which keeps it self-contained and in the target band.

## Protocol notes

Two engines needed care to expose UCI, recorded so it is not rediscovered:

- **Jazz 8.40** — its standalone UCI interface (`ucijazz`) is abandoned and no longer compiles against 8.40 (it calls removed functions). The maintained `xbjazz` binary implements both XBoard and UCI, so that is what is built and installed. This is why upstream ships `WANT_UCI` off by default.
- **Sjaak II 1.4.1** — despite the `xboard.cc` filename, the single `sjaakii` binary speaks UCI natively in standard-chess mode. Packaged as-is.
- **EXchess / Leaf** — the historical EXchess spoke only XBoard/CECP. UCI was added only in the author's 2026 restart of the codebase (`dan-homan/Leaf`), *after* NNUE. There is no "classic EXchess speaking UCI" to pin, so this ships the first UCI-capable commit built with NNUE left at its `define.h` default of 0 — i.e. the genuine classic hand-crafted evaluation exposed over the newer UCI layer. Kept, with the provenance documented in `engines/exchess.nix`.

## License discrepancies (included, but noted)

Redistributable either way, so inclusion is sound; recorded for accuracy and a possible upstream question.

- **Deepov** (`RomainGoussault/Deepov`) — the `LICENSE` file is GPLv2 text, but every source header carries the GPLv3 "version 3 … or any later version" notice. Packaged as `gpl3Plus` per the governing per-file notices.
- **Maxima2 / qm2** (`hof/qm2`) — same pattern: GPLv2 `LICENSE` file, GPLv3+ source headers. Packaged as `gpl3Plus`.
- **Cinnamon** — GPLv3+ headers vs an LGPL-3.0 `LICENSE` file (noted earlier); treated as GPLv3+, the conservative reading.

## Platform-gated (x86-only, not build-verified on aarch64)

These have no NEON or scalar fallback — unconditional `<immintrin.h>` or inline x86 asm — so they are restricted to `x86_64-linux` / `x86_64-windows` in their `meta.platforms` and skipped on this repo's aarch64-darwin host. Each must be build-verified on an x86_64 runner before being relied upon.

- **Obsidian** — `src/simd.h`/`bitboard.h` include `<immintrin.h>` unconditionally; NNUE inference is AVX512/AVX2/SSSE3 only.
- **Gull** (LazyGull) — inline `bsfq`/`bsrq` asm, `_mm_popcnt_u64`, and fixed-address GNU-ld link flags.
- **Igel** — `src/nnue.h` includes `<immintrin.h>` unconditionally; NNUE written entirely against AVX/SSE intrinsics.
