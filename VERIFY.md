# Open verification: the Linux-only Lc0 backends

Lc0 is packaged as one build per backend (see `engines/lc0.nix`). Two of the four were developed and verified on aarch64-darwin; the other two **cannot be built or run on macOS at all**, so they have never been compiled, let alone executed. This page is the checklist for closing that gap on a Linux box. Everything here needs x86_64-linux (or aarch64-linux) with Nix and flakes.

| Variant | Built | Ran a real search | Status |
|---|---|---|---|
| `lc0` (CPU) | yes, aarch64-darwin + CI on Linux | yes | verified |
| `lc0-metal` | yes, aarch64-darwin | yes | verified |
| `lc0-opencl` | **never** | **never** | evaluates only; in CI's `checks`, so the next Linux CI run is its first build |
| `lc0-cuda` | **never** | **never** | excluded from CI by design (unfree) — nothing will ever build it automatically |

The OpenCL entries in `docs/lc0-networks.md` were chosen by checking each network's `describenet` output against the backend's acceptance test in the Lc0 source, **not** by loading them. That reasoning is sound but untested, and it is the single most likely thing on this page to be wrong.

Prerequisite: the Lc0 rework lives on the `lc0-backends-and-updater-fix` branch, not yet on `main` — check it out before testing, and confirm `engines/lc0.nix` has the four variants and `flake.nix` has the `neverCached` exclusion.

## 1. `lc0-opencl` compiles

```console
$ nix build .#lc0-opencl --print-build-logs
```

The interesting part is not that it links, but that meson found OpenCL. If the backend is missing the build still succeeds — lc0 silently produces a BLAS-only binary when `has_opencl` is false — so the build alone proves nothing. Check the binary:

```console
$ printf 'uci\nquit\n' | ./result/bin/lc0 2>/dev/null | grep 'option name Backend type'
```

**Pass:** `opencl` appears in the `var` list. **Fail:** only `blas eigen trivial random …`, which means `-Dopencl=true` and `-Dopencl_include=` did not take and the variant is OpenCL in name only.

## 2. `lc0-opencl` runs an OpenCL-compatible network

Needs an OpenCL ICD installed on the host — the derivation supplies the loader (`ocl-icd`), not a driver. On Arch that is the vendor package for your GPU (`opencl-nvidia`, `rocm-opencl-runtime`, `intel-compute-runtime`, or `opencl-mesa` for rusticl); `clinfo` should list at least one platform before you start.

```console
$ curl -LO https://storage.lczero.org/files/networks-contrib/sv-t60-3010.pb.gz
$ nix hash file --sri --type sha256 sv-t60-3010.pb.gz
  # expect: sha256-LlAsOU5eVXZkaUZCDC12P2MWW4lKPeqaFdMv7QWwewQ=

$ { printf 'uci\nisready\nposition startpos\ngo nodes 20000\n'; sleep 60; printf 'quit\n'; } \
    | ./result/bin/lc0 --weights=./sv-t60-3010.pb.gz --backend=opencl
```

**Pass:** a `bestmove` line, and `nps` clearly above what the same box does with `--backend=blas`. Worth recording both numbers — the CPU-vs-GPU ratio is the only evidence the GPU is actually doing the work.

Smaller alternative if `sv-t60-3010` (131 MB, 30×384) is too slow: `744706.pb.gz` or `LD2.pb.gz`, 6.1 MB each, `sha256-Qw+awinq/BtMMFuiCt9+S0xdego/AyMHOYrI40m3Isg=` and `sha256-BLohTOEnfs6beB6KHsHvLdTY8pT0lsyOb+8yXymNtgo=`.

## 3. `lc0-opencl` rejects a modern network (negative test)

This is the claim `docs/lc0-networks.md` is built on, and it should be confirmed rather than assumed.

```console
$ curl -LO https://storage.lczero.org/files/networks-contrib/t1-256x10-distilled-swa-2432500.pb.gz
$ { printf 'uci\nisready\nposition startpos\ngo nodes 100\n'; sleep 10; printf 'quit\n'; } \
    | ./result/bin/lc0 --weights=./t1-256x10-distilled-swa-2432500.pb.gz --backend=opencl
```

**Pass:** it throws `Network format NETWORK_ATTENTIONBODY_WITH_HEADFORMAT is not supported by OpenCL backend` and exits. **Surprise result worth reporting:** if it loads and plays, the OpenCL section of `docs/lc0-networks.md` is too pessimistic and the whole per-backend split needs revisiting.

## 4. `lc0-cuda` evaluates and compiles

Unfree, so it needs both the env var and `--impure` (the flake cannot read the env var otherwise):

```console
$ NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#lc0-cuda --print-build-logs
```

This is the least-tested expression in the repo: the meson probes (`cc.find_library('cublas')`, `find_library('cudart')`, `find_program('nvcc')`) and the `-Dcudnn_include=` paths were written against Lc0's `meson.build` without ever being run. Plausible failure modes, in rough order of likelihood: nvcc not found because `cudaPackages.cuda_nvcc` does not land on `PATH` under `strictDeps`; cublas/cudart headers not found because the `-Dcudnn_include=` comma-separated list needs a different form; nvcc rejecting the host compiler and wanting `-Dnvcc_ccbin=`.

Then confirm the backend is actually in the binary — same trap as OpenCL, since Lc0 skips CUDA silently when the probes fail:

```console
$ printf 'uci\nquit\n' | ./result/bin/lc0 2>/dev/null | grep 'option name Backend type'
```

**Pass:** `cuda` appears in the `var` list.

## 5. `lc0-cuda` runs on the GPU

On Arch (not NixOS), a Nix-built CUDA binary still needs the host driver's `libcuda.so.1`, which is not in the Nix closure. If it fails with `libcuda.so.1: cannot open shared object file`, the usual fixes are `nixglhost`/`nixGL`, or pointing the loader at the host driver directory for a one-off check.

```console
$ curl -LO https://storage.lczero.org/files/networks-contrib/BT4-1024x15x32h-swa-6147500-policytune-332.pb.gz
$ nix hash file --sri --type sha256 BT4-1024x15x32h-swa-6147500-policytune-332.pb.gz
  # expect: sha256-5q2p1sSnab+rOqCEjYLK64CapF+D5sYF/FijHSG91hg=

$ { printf 'uci\nisready\nposition startpos\ngo nodes 20000\n'; sleep 60; printf 'quit\n'; } \
    | ./result/bin/lc0 --weights=./BT4-*.pb.gz --backend=cuda
```

**Pass:** a `bestmove`, and an `nps` figure far above the 159 nps this net managed on an integrated Apple GPU. BT4 is listed as the strongest option in `docs/lc0-networks.md` on the assumption a discrete card makes it pay off; this is the measurement that supports or refutes that.

## 6. Sanity: the moves are still right

Whichever backends come up, one tactical position confirms the net and search are wired correctly and not just producing legal noise:

```console
$ { printf 'uci\nisready\nposition fen 2rr3k/pp3pp1/1nnqbN1p/3pN3/2pP4/2P3Q1/PPB4P/R4RK1 w - - 0 1\ngo nodes 20000\n'; \
    sleep 60; printf 'quit\n'; } | ./result/bin/lc0 --weights=<net> --backend=<backend>
```

**Pass:** `bestmove g3g6`. That is WAC.001; `lc0-metal` finds it in about a thousand nodes and reports mate in 2.

## What to capture

For each check: the command, whether it passed, and the `nps` figure where there is one. The two numbers most worth having are OpenCL-vs-BLAS on the same box and CUDA-vs-BT4-on-Apple-GPU — both feed straight back into the recommendations in `docs/lc0-networks.md`, which currently carries an explicit note that neither backend was ever loaded.

If anything here fails, the fix belongs in `engines/lc0.nix`; the CUDA variant in particular has never had a single line of it executed.

---

## Unrelated open items

Not Linux-specific and not part of the above, but open in this repository:

- **The nightly `update` workflow cannot open its PR.** `Settings → Actions → General → Workflow permissions` needs *Allow GitHub Actions to create and approve pull requests*; the API currently reports `can_approve_pull_request_reviews: false`. Four otherwise-green runs died at that final step.
- **`blackmarlin` cannot be fetched.** Upstream's Git-LFS budget is exhausted (`jnlt3/blackmarlin` returns HTTP 403 `This repository exceeded its LFS budget` for the 29 MB `nn/default.bin`), so any cache miss on its source fails the build. Nothing in this repo can fix it; the options are mirroring the net, pushing the source FOD to the R2 cache, or dropping the engine until upstream restores the budget.
- **`ci/update-nets.sh` does not exist**, so the NNUE net-refresh step in `ci/update.sh` is silently skipped by its `[ -x ]` guard.
