# Lc0 networks

This flake ships Lc0 as an executable only — no weights. The right network depends on which backend you run, how much VRAM you have, and how much time per move is on offer, and that matrix is far larger than this repository should try to enumerate. See the header of `engines/lc0.nix` for the reasoning. This page is the shortlist: known-good, widely-used networks per backend, in a few sizes each.

Pass one at runtime:

```console
$ lc0 --weights=/path/to/network.pb.gz
```

Each variant installs under its own name — `lc0`, `lc0-opencl`, `lc0-metal`, `lc0-cuda` — so that all of them survive side by side in the `chess-engines-all` bundle. Substitute the one you built for `lc0` in the examples below.

All files below live under `https://storage.lczero.org/files/networks-contrib/`. Sizes are the actual `Content-Length` of each file; architectures are what `lc0 describenet --weights=<file>` reports, checked against every net listed here rather than inferred from the filename.

## The compatibility trap: OpenCL cannot run modern nets

Backends do not all accept the same network architectures, and picking wrong is a hard failure at load time, not a slowdown.

| Backend | Classical / SE-ResNet | Attention-body ("transformer") |
|---|---|---|
| `lc0` (BLAS, eigen) | yes | yes |
| `lc0-metal` | yes | yes |
| `lc0-cuda` | yes | yes |
| `lc0-opencl` | yes | **no** |

Lc0's OpenCL backend accepts only `NETWORK_CLASSICAL_WITH_HEADFORMAT` or `NETWORK_SE_WITH_HEADFORMAT`, only classical or convolutional policy, only classical or WDL value, and only RELU as the default activation — see `MakeOpenCLNetwork` in `src/neural/backends/opencl/network_opencl.cc`. Every current T1/T2/T3/BT network fails all three of those tests: they are attention-body with attention policy and MISH activation. Handing one to `lc0-opencl` throws `Network format NETWORK_ATTENTIONBODY_WITH_HEADFORMAT is not supported by OpenCL backend` and the engine exits.

So OpenCL is restricted to the pre-attention era. If you have an NVIDIA card, `lc0-cuda` is both faster and unrestricted; OpenCL is the fallback for AMD/Intel GPUs, where the ceiling is a 2021-era network.

## CPU — `lc0`

The CPU backend is roughly 5× slower than an integrated GPU and 39× slower on eigen than on Metal (measured below), so size down aggressively. Anything past the mid entry is only sensible at long time controls.

| Network | Size | Architecture |
|---|---:|---|
| `744706` | 6.1 MB | SE-ResNet, 10 blocks × 128 filters |
| `t1-256x10-distilled-swa-2432500` | 35.4 MB | attention, 10 encoders × 8 heads — **recommended default** |
| `t1-512x15x8h-distilled-swa-3395000` | 142.8 MB | attention, 15 encoders × 8 heads |

## Apple GPU — `lc0-metal`

| Network | Size | Architecture |
|---|---:|---|
| `t1-256x10-distilled-swa-2432500` | 35.4 MB | attention, 10 enc × 8 heads |
| `t1-512x15x8h-distilled-swa-3395000` | 142.8 MB | attention, 15 enc × 8 heads — **recommended default** |
| `BT3-768x15x24h-swa-2790000` | 182.1 MB | attention multihead, 15 enc × 24 heads |
| `BT4-1024x15x32h-swa-6147500-policytune-332` | 364.9 MB | attention multihead, 15 enc × 32 heads |

BT4 loads and plays correctly on Metal, but on an integrated Apple GPU it ran at **159 nps** here versus a few thousand for `t1-256` — strong per node, far too few nodes. Treat BT4 as a discrete-GPU network; on Apple silicon the distilled T1 nets are the practical choice.

## NVIDIA — `lc0-cuda`

The unrestricted backend: every architecture works, and a discrete card has the throughput to make the large nets pay off.

| Network | Size | Architecture |
|---|---:|---|
| `t1-512x15x8h-distilled-swa-3395000` | 142.8 MB | attention, 15 enc × 8 heads |
| `BT3-768x15x24h-swa-2790000` | 182.1 MB | attention multihead, 15 enc × 24 heads |
| `BT4-1024x15x32h-swa-6147500-policytune-332` | 364.9 MB | attention multihead, 15 enc × 32 heads — **strongest of these** |

## AMD / Intel GPU — `lc0-opencl`

Pre-attention networks only, per the compatibility section above.

| Network | Size | Architecture |
|---|---:|---|
| `744706` | 6.1 MB | SE-ResNet, 10 blocks × 128 filters |
| `LD2` | 6.1 MB | SE-ResNet, 10 blocks × 128 filters |
| `sv-t60-3010` | 131.0 MB | SE-ResNet, 30 blocks × 384 filters — **strongest OpenCL-compatible net here** |

Both the acceptance rule and these entries have now been run rather than
reasoned about — on an AMD Radeon 780M (gfx1103, integrated), ROCm ICD:

| Net | Backend | nps (20k nodes, startpos) |
|---|---|---:|
| `744706` | `opencl` | 4,248 |
| `744706` | `eigen` (CPU, 16 threads) | 243 |
| `sv-t60-3010` | `opencl` | 408 |

The 17× gap on the same net and the same box is the evidence the GPU is doing
the work, and it is the number to compare against when checking a new card.
`sv-t60-3010` loads and plays, so the "strongest OpenCL-compatible" label above
is now a measurement; at 408 nps on *integrated* graphics it is still the slow
end of usable, and `744706` is the better trade below about a second a move.
A discrete AMD card should move both figures a long way up.

## Verifying a download

Every hash below was computed from the file actually served at the URL above, in SRI form so it can be pasted straight into a `fetchurl` if you decide to pin one locally:

| Network | sha256 (SRI) |
|---|---|
| `744706` | `sha256-Qw+awinq/BtMMFuiCt9+S0xdego/AyMHOYrI40m3Isg=` |
| `LD2` | `sha256-BLohTOEnfs6beB6KHsHvLdTY8pT0lsyOb+8yXymNtgo=` |
| `t1-256x10-distilled-swa-2432500` | `sha256-vCemyuitNvK5qApq2dq7DW/aJbHn9IGnm8NZ4U9WNAY=` |
| `sv-t60-3010` | `sha256-LlAsOU5eVXZkaUZCDC12P2MWW4lKPeqaFdMv7QWwewQ=` |
| `t1-512x15x8h-distilled-swa-3395000` | `sha256-H9sVGeWwLgPx2SAeyOuV9kDjLMZFmk8UwOq2iQ3Al+g=` |
| `BT3-768x15x24h-swa-2790000` | `sha256-4wZ3V9H8LfxmlHsh0VrODO30xUJU/B3oPXfDeKPouOE=` |
| `BT4-1024x15x32h-swa-6147500-policytune-332` | `sha256-5q2p1sSnab+rOqCEjYLK64CapF+D5sYF/FijHSG91hg=` |

To check a file yourself, or to re-derive a hash after upstream rotates a net:

```console
$ nix hash file --sri --type sha256 network.pb.gz
$ lc0 describenet --weights=network.pb.gz     # architecture, policy, value, activation
```

`describenet` is the authoritative answer to "will this net run on my backend" — compare its `Network:`, `Policy:` and `Default activation:` lines against the OpenCL constraints above.

## What was measured here

Throughput figures on this page come from one machine (aarch64-darwin, Apple silicon, integrated GPU), startpos, `lc0-metal` unless stated: `t1-256` reached 2,787 nps over a 20k-node run including warmup and 5,907 nps sustained on a longer one, against 545 nps on `blas` and 71 nps on `eigen` for the same workload; BT4 managed 159 nps. They are the ratios between backends and net sizes on one class of hardware, not a benchmark — a discrete GPU changes the picture entirely, and is the reason the large nets are listed at all.

Architectures and sizes were verified for every network listed.

The OpenCL half of this page used to carry a caveat that nothing on it had ever
been loaded, only reasoned about from the acceptance test in the Lc0 source.
That gap is closed: on x86_64-linux with an AMD Radeon 780M, `744706` and
`sv-t60-3010` both load and play on `lc0-opencl` (figures in the OpenCL section
above), and the rejection is verbatim what was predicted —
`t1-256x10-distilled-swa-2432500` throws `Network format
NETWORK_ATTENTIONBODY_WITH_HEADFORMAT is not supported by OpenCL backend` and
exits. `describenet` output was confirmed against every claim in the
compatibility table. The reasoning was sound; it is now also tested.

`lc0-cuda` remains the untested one, and the caveat now belongs only to it. It
compiles and reports `cuda`, `cuda-auto` and `cuda-fp16` among its backends, but
no net on this page has been run through it — the Linux box available had an AMD
GPU, so nothing here has executed a single CUDA kernel. The BT4 recommendation
in the NVIDIA section is still an extrapolation from the Apple-GPU figure, not a
measurement.
