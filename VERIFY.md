# Verification: the Linux-only Lc0 backends

Lc0 is packaged as one build per backend (see `engines/lc0.nix`). Two of the
four were developed on aarch64-darwin; the other two cannot be built or run on
macOS at all, so they had never been compiled, let alone executed. This page
was the checklist for closing that gap. It has now been run on x86_64-linux
(Arch, 16 cores, AMD Radeon 780M / gfx1103 integrated GPU, ROCm ICD).

**Both Linux backends were broken, in the same silent way, and neither the
build nor CI said a word.** Details below; the fixes are in `engines/lc0.nix`.

| Variant | Built | Ran a real search | Status |
|---|---|---|---|
| `lc0` (CPU) | yes | yes | verified |
| `lc0-metal` | yes, aarch64-darwin | yes | verified |
| `lc0-opencl` | **yes, after a fix** | **yes** | verified end to end |
| `lc0-cuda` | **yes, after a fix** | no NVIDIA GPU available | compiles and registers `cuda`; kernels never executed |

## What was wrong

Three defects, all found by actually running the checklist.

**1. `lc0-opencl` contained no OpenCL backend.** Lc0 gates the backend on
`has_opencl`, which requires both a header probe and
`cc.find_library('OpenCL', dirs: opencl_libdirs)`. `opencl_libdirs` defaults to
`['/opt/cuda/lib64/', '/usr/local/cuda/lib64/']`, and a non-empty `dirs`
argument makes meson search *those directories instead of* the compiler's own
path — so `ocl-icd` sitting in `buildInputs` was never found. `-Dopencl=true`
became a no-op, lc0 emitted a BLAS-only binary, the build succeeded, the
install check passed, and the artifact was "OpenCL" in name only. Fixed with
`-Dopencl_libdirs=${ocl-icd}/lib`.

**2. `lc0-opencl` then failed to compile.** With the backend actually enabled,
lc0's vendored `third_party/opencl.hpp` breaks against current
`opencl-headers`: it references `CL_EXTERNAL_MEMORY_HANDLE_D3D11_TEXTURE_KHR`
and friends, which now live in the Windows-only part of `cl_ext.h`. Lc0's
`OpenCL.h` prefers a real `CL/opencl.hpp` when `__has_include` finds one, so
adding `opencl-clhpp` to `buildInputs` sidesteps the vendored copy entirely.

**3. `lc0-cuda` had the identical libdirs bug** (`cudnn_libdirs`, same
`find_library(dirs:)` shape), plus two more once past it: the C++ half of the
backend needs `crt/host_defines.h`, which ships with `cuda_nvcc` rather than
`cuda_cudart` and so had to be added to `-Dcudnn_include`; and `native_cuda`
defaults to **true**, passing `nvcc -arch=native`. On any builder without an
NVIDIA card — CI, or anything that would cut a release — nvcc cannot detect a
GPU, warns, and falls back to a default arch, baking one guessed architecture
into a cached artifact. Now `-Dnative_cuda=false`, giving `-arch=all-major`.
Verified with `cuobjdump`: the binary carries sm_50, 60, 70, 80, 90, 100 and
120.

**Guard against a repeat.** The install check now asserts that the variant's
backend is actually present, not just that the binary speaks UCI — see
`expectBackend` in `engines/lc0.nix`. Confirmed in both directions: it passes
on the fixed build, and re-introducing the libdirs bug makes it fail with
`FAIL: this is lc0-opencl, but 'opencl' is not among its backends`. Only
`opencl` and `cuda` need it; `-Dmetal` is a meson *feature* set to `enabled`,
which already fails loudly at configure time rather than silently skipping.

## Results

### 1. `lc0-opencl` compiles, with OpenCL in it — **pass**

```console
$ nix build .#lc0-opencl
$ printf 'uci\nquit\n' | ./result/bin/lc0-opencl 2>/dev/null | grep 'option name Backend type'
option name Backend type combo default opencl var opencl var eigen var trivial …
```

`opencl` is present and is the default. Before the fix this read
`default eigen var eigen var trivial …` — the failure mode the checklist
predicted.

### 2. `lc0-opencl` runs an OpenCL-compatible network — **pass**

20k nodes from startpos, ROCm ICD on the 780M:

| Net | Backend | nps | bestmove |
|---|---|---:|---|
| `744706` | `opencl` | 4,248 | e2e4 |
| `744706` | `eigen` (16 threads) | 243 | e2e4 |
| `sv-t60-3010` | `opencl` | 408 | d2d4 |

**17× over the CPU on the same net and the same box** — the GPU is doing the
work. `sv-t60-3010` (131 MB, 30×384) loads and plays, so its "strongest
OpenCL-compatible net" billing in `docs/lc0-networks.md` is now measured rather
than inferred; at 408 nps on integrated graphics it is the slow end of usable.

Host note, not a packaging issue: nixpkgs' `ocl-icd` looks in
`/run/opengl-driver/etc/OpenCL/vendors`. On Arch, point `OCL_ICD_VENDORS` at an
ICD file. Arch's own `/etc/OpenCL/vendors/amdocl64.icd` refers to
`/opt/rocm/lib/libamdocl64.so`, which drags in host `libstdc++`/glibc 2.44 and
collides with the Nix closure's 2.42 — the classic non-NixOS driver problem.
Using nixpkgs' `rocmPackages.clr` as the ICD avoids the mixing entirely, since
only the kernel interface (`/dev/kfd`) is then host-side:

```console
$ echo "$(nix build --no-link --print-out-paths nixpkgs#rocmPackages.clr)/lib/libamdocl64.so" > icd/amdocl64.icd
$ export OCL_ICD_VENDORS=$PWD/icd
```

### 3. `lc0-opencl` rejects a modern network — **pass, verbatim**

`t1-256x10-distilled-swa-2432500` throws exactly what `docs/lc0-networks.md`
predicted and exits:

```
error Network format NETWORK_ATTENTIONBODY_WITH_HEADFORMAT is not supported by OpenCL backend.
```

`describenet` also confirms every architecture claim in that document:
`744706` and `sv-t60-3010` are `NETWORK_SE_WITH_HEADFORMAT` with
`POLICY_CONVOLUTION`; `t1-256` is `NETWORK_ATTENTIONBODY_WITH_HEADFORMAT` /
`POLICY_ATTENTION` / `DEFAULT_ACTIVATION_MISH`. The reasoning behind the
per-backend split was sound, and is now tested rather than assumed.

### 4. `lc0-cuda` evaluates and compiles — **pass**

```console
$ NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#lc0-cuda
$ printf 'uci\nquit\n' | ./result-cuda/bin/lc0-cuda 2>/dev/null | grep 'option name Backend type'
option name Backend type combo default cuda-auto var cuda-auto var cuda var cuda-fp16 var eigen …
```

This expression had never had a line of it executed. It needed the three fixes
above; the checklist's guesses at the likely failure modes were close — the
`cudnn_include` list did need a different form (an extra entry), though nvcc
was found on `PATH` under `strictDeps` without trouble and `-Dnvcc_ccbin=` was
never needed.

### 5. `lc0-cuda` runs on the GPU — **not run**

The Linux box available has an AMD GPU. Nothing here has executed a CUDA
kernel, and the BT4 recommendation in `docs/lc0-networks.md` remains an
extrapolation from the 159 nps Apple-GPU figure. **This is the one item on the
original checklist still open**, and it needs an NVIDIA box:

```console
$ curl -LO https://storage.lczero.org/files/networks-contrib/BT4-1024x15x32h-swa-6147500-policytune-332.pb.gz
  # expect: sha256-5q2p1sSnab+rOqCEjYLK64CapF+D5sYF/FijHSG91hg=
$ { printf 'uci\nisready\nposition startpos\ngo nodes 20000\n'; sleep 60; printf 'quit\n'; } \
    | ./result-cuda/bin/lc0-cuda --weights=./BT4-*.pb.gz --backend=cuda
```

On Arch rather than NixOS this will also need the host driver's `libcuda.so.1`,
which is not in the Nix closure — `nixglhost`/`nixGL`, or the same
ICD-substitution trick used for ROCm above.

#### Doing it on EC2

No NVIDIA hardware is needed for more than an hour, so a spot instance is the
cheap way to close this.

**Instance: `g4dn.2xlarge`.** The T4 is the cheapest NVIDIA GPU AWS rents, and
any NVIDIA GPU answers the pass/fail question. Take the `2xlarge` (8 vCPU)
rather than the `xlarge` (4 vCPU) for the *build*, not the run: `lc0-cuda` is
compiled with `-Dnative_cuda=false`, so nvcc emits SASS for every major
architecture (sm_50 through sm_120) and that is a long compile on four cores.
Step up to `g5.2xlarge` (A10G, Ampere) only if the goal is a BT4 throughput
number worth quoting — the T4 is a 2018 inference card and will understate what
a current desktop GPU does, which matters because the BT4 recommendation in
`docs/lc0-networks.md` is an extrapolation. Avoid `g4ad` — that is AMD, no CUDA.

**AMI: "Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 24.04)".** The
point is that the NVIDIA kernel driver is already installed and signed, which
is the one step that most often eats an afternoon. The CUDA toolkit it also
carries is irrelevant here — Nix builds its own — so the *Base* image is
enough; the full Deep Learning AMI just adds frameworks you will not use. Do
not pick a bare Ubuntu AMI unless you want to install the driver and reboot
first. Search the AMI catalogue by that name rather than pasting an ID: IDs are
region-specific and are re-cut on every driver bump.

**Root volume: 100 GB gp3.** Not optional. The unfree CUDA closure is several
GB before lc0 itself, and Ubuntu AMIs default to a root volume that will not
hold it. Running out of disk halfway through a CUDA build is a slow way to
discover this.

```console
# on the instance
$ nvidia-smi                      # driver is present and sees the GPU
$ curl -fsSL https://install.determinate.systems/nix | sh -s -- install
$ git clone https://github.com/obazin/nix-chess-suite && cd nix-chess-suite
$ git checkout lc0-backends-and-updater-fix

$ NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#lc0-cuda -o result-cuda --print-build-logs
$ printf 'uci\nquit\n' | ./result-cuda/bin/lc0-cuda 2>/dev/null | grep 'option name Backend type'
```

Then the network and the search, per the commands above. `libcuda.so.1` still
comes from the host driver rather than the Nix closure, so a run that dies with
`libcuda.so.1: cannot open shared object file` is the expected impurity, not a
packaging bug. `nixglhost` (`github:numtide/nix-gl-host`) exists to bridge
exactly that — check its README for the current invocation before reaching for
`LD_LIBRARY_PATH`, which works but mixes the host's glibc into the Nix closure
and is how the ROCm side went wrong on Arch.

NixOS is the alternative that sidesteps that entirely — `hardware.nvidia` puts
the driver under `/run/opengl-driver/lib`, which is exactly where a
nixpkgs-built CUDA binary looks — but on a throwaway box the driver-preinstalled
Ubuntu image gets to an answer faster than configuring and rebuilding NixOS.

Instance families, images and prices all move; confirm against the console when
you launch. And terminate it — a forgotten GPU instance costs more than this
whole exercise.

### 6. Sanity: the moves are still right — **pass, with the criterion corrected**

The checklist asked for `bestmove g3g6` (WAC.001). `lc0-opencl` does not play
it — and the reason is the network, not the backend. Two controls isolate the
variable:

| Backend | Net | Nodes | Result |
|---|---|---:|---|
| `opencl` | `744706` (SE) | 20k | `f6h5`, cp 709 |
| `eigen` | `744706` (SE) | 20k | `f6h5`, cp 717 |
| `opencl` | `sv-t60-3010` (SE) | 20k | `f6h5` |
| `eigen` | `t1-256` (attention) | 222 | **`g3g6`, mate 2** |

Hold the net fixed and swap the backend: OpenCL and the CPU reference agree
move-for-move, within 8 cp. Two independent implementations computing the same
answer is what a correct backend looks like. Hold the backend fixed and swap
the net: the attention net finds the mate in 222 nodes, reproducing on CPU
exactly what `lc0-metal` was reported to do.

So `g3g6` is a property of attention networks — and attention networks are
precisely what the OpenCL backend cannot load (check 3). **No
OpenCL-compatible net can meet that bar**, and the original criterion was
unreachable by construction. The right sanity check for `lc0-opencl` is
agreement with the CPU backend on the same net, which is the row-pair above.
The `f6h5` lines are all winning by about +7; they simply are not the mate.

## Still open

- **`lc0-cuda` has never executed a kernel** (check 5). Needs an NVIDIA host.
- **`ci/update-nets.sh` does not exist** — confirmed still true, so the NNUE
  net-refresh step in `ci/update.sh:120` is silently skipped by its `[ -x ]`
  guard. Same silent-skip shape as the two backend bugs above.

### Closed

- ~~The nightly `update` workflow cannot open its PR.~~ Fixed at the repository
  level: `can_approve_pull_request_reviews` is now `true`.
  `default_workflow_permissions` is deliberately left at `read` — `update.yml`
  declares its own `permissions:` block, which is what let those runs push a
  branch and get as far as the PR step in the first place, so the restrictive
  default costs nothing.
- ~~`blackmarlin` cannot be fetched.~~ Still true upstream, and no fix was
  available: forks share the parent's LFS budget and return the same 403, and
  the net is not a release asset, so there was nothing to mirror and no source
  to push to the R2 cache. The engine has been removed from the collection
  rather than carried as a package that nobody can build. Reason and the last
  known-good pin are recorded in `docs/excluded.md`, so restoring it is a
  matter of re-adding the file if upstream restores its budget.
