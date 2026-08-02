{ lib, stdenv, fetchFromGitHub, meson, ninja, pkg-config, python3, zlib, gtest
, eigen, abseil-cpp, ocl-icd, opencl-headers, opencl-clhpp, cudaPackages, lld
, ... }:

# Full-strength Leela Chess Zero, distinct from the Maia family.
#
# Built from lc0's own sources rather than wrapping nixpkgs' lc0. The pin below
# is a real `src`, so the nightly updater bumps this engine like every other one
# in the strong tier — as a wrapper, lc0's version moved only when the flake's
# nixpkgs input did, and nix-update had no `src` to work with at all.
#
# NO NETWORK SHIPS WITH ANY OF THESE, deliberately. Only the executable is
# pinned; the weights are the consumer's call:
#
#   lc0 --weights=/path/to/network.pb.gz
#
# The right net is a function of the client's hardware — backend, VRAM, and the
# time control on offer. A T80/BT4-class net that dominates on a GPU is unusably
# slow on a CPU backend, and the distilled nets trade the other way. That matrix
# is far too large to enumerate here, and pinning one net for everyone would
# ship a 150 MB file that is wrong for most people. Networks live at
# https://storage.lczero.org/files/ (guide: https://lczero.org/play/networks/).
#
# docs/lc0-networks.md carries a shortlist per backend, in several sizes, with
# verified hashes — including the one trap worth knowing before you pick: the
# OpenCL backend rejects every attention-body net (it takes classical/SE nets
# with RELU only), so lc0-opencl cannot run any current T1/T2/T3/BT network.
#
# The Maia family is the deliberate exception and keeps its nets pinned
# (engines/maia.nix): those are rating-targeted and tiny, and a maia-1500
# without the 1500 net is not an engine at all.
#
# One variant per backend, each a separate build. lc0 selects a backend at
# runtime from the ones compiled into the binary, so rather than one build whose
# contents depend on what happens to be in the closure, each variant here states
# exactly which backend it carries and switches every other one off. BLAS (eigen
# on Linux, Accelerate on macOS) stays in all of them as the fallback lc0 uses
# when its accelerated backend finds no device.
#
#   lc0          CPU only. The portable, cached default.
#   lc0-opencl   Vendor-neutral GPU: links the OpenCL ICD loader, not a driver,
#                and picks up whatever NVIDIA/AMD/Intel ICD the host installs.
#   lc0-cuda     NVIDIA. Unfree toolchain, so it is never built or cached by CI
#                (see the exclusion in flake.nix) — build it yourself with
#                NIXPKGS_ALLOW_UNFREE=1.
#   lc0-metal    Apple GPU. macOS only, per Metal.

let
  version = "0.32.1";

  src = fetchFromGitHub {
    owner = "LeelaChessZero";
    repo = "lc0";
    rev = "v${version}";
    hash = "sha256-Dvq698ZfYumoax7i1nN5GwTQKXgby9+TdTZT6C7/jgc=";
    fetchSubmodules = true;
  };

  # Every backend named explicitly, so a variant is what its name says and
  # nothing more. Left to itself lc0 would decide from the closure: `metal`
  # defaults to `auto` and self-enables on any macOS build, and `plain_cuda`
  # defaults to true, waiting for an nvcc to appear. `onnx` and `dx` are off in
  # every variant — no build here carries an ONNX Runtime or DirectX SDK.
  backendFlags = { cuda ? false, opencl ? false, metal ? false }: [
    "-Dplain_cuda=${lib.boolToString cuda}"
    "-Dcudnn=false"
    "-Dopencl=${lib.boolToString opencl}"
    "-Dmetal=${if metal then "enabled" else "disabled"}"
    "-Donnx=false"
    "-Ddx=false"
  ];

  mkLc0 =
    { variant
    , backend
    , platforms
    , nativeBuildInputs ? [ ]
    , buildInputs ? [ ]
    , mesonFlags ? [ ]
    , expectBackend ? null
    }:
    stdenv.mkDerivation {
      pname = if variant == null then "lc0" else "lc0-${variant}";
      inherit version src;

      # lc0's meson.build pulls abseil in as a meson subproject, which would
      # need the network mid-build; point it at the abseil already in the
      # closure. The third replacement drops a `cc.has_header('Eigen/Core')`
      # probe that fails on the include layout nixpkgs' eigen ships. Both mirror
      # nixpkgs' own lc0 expression. --replace-fail is deliberate: if an upgrade
      # moves these lines, the bump fails loudly instead of quietly producing a
      # lesser build.
      postPatch = ''
        substituteInPlace meson.build \
          --replace-fail "absl = subproject('abseil-cpp', default_options : ['warning_level=0', 'cpp_std=c++20'])" "" \
          --replace-fail "deps += absl.get_variable('absl_container_dep').as_system()" "deps += [dependency('absl_flat_hash_map'), dependency('absl_cleanup'), dependency('absl_base')]" \
          --replace-fail "if eigen_dep.found() and cc.has_header('Eigen/Core')" "if eigen_dep.found()"
        patchShebangs --build scripts/*
      '';

      strictDeps = true;

      nativeBuildInputs = [ meson ninja pkg-config python3 ] ++ nativeBuildInputs;
      buildInputs = [ eigen gtest zlib abseil-cpp ] ++ buildInputs;

      mesonFlags = [
        # No embedded net — see the header.
        "-Dembed=false"

        # lc0 defaults native_arch on, which puts -march=native into a binary
        # that CI builds once and the shared cache then serves to everyone: an
        # engine tuned to the runner's CPU that SIGILLs on an older one. The
        # rest of the collection strips these flags for the same reason (see
        # stripArchFlags in lib/mkEngine.nix) — the portable baseline is the
        # cacheable artifact, and -march=native belongs to an opt-in native
        # build.
        "-Dnative_arch=false"
        "-Dispc_native_only=false"
      ] ++ backendFlags backend ++ mesonFlags;

      enableParallelBuilding = true;

      doCheck = true;

      # Same guarantee as mkEngine: the binary must speak UCI. It stops at the
      # handshake, because with no net pinned there is nothing to search with —
      # lc0 answers `uci` from its built-in option table before any weights are
      # touched, and before it opens a GPU device, so this is also the right
      # depth of check for the accelerated variants on a driverless builder.
      # The net-loading path is covered by the Maia engines, which pin theirs
      # and do run a real search in their install check.
      #
      # expectBackend then asserts the variant is what its name claims. This is
      # not belt-and-braces: `-Dopencl` and `-Dplain_cuda` are plain booleans
      # that meson ANDs with its own library/header probes, so a probe that
      # comes up empty downgrades the build to BLAS-only *and still succeeds*.
      # A green CI run on a binary with no GPU backend in it is exactly the
      # failure this repo shipped before — both variants were configured with
      # libdirs that pointed nowhere, and nothing anywhere said so. The backend
      # list comes from a compile-time registry, so this works on a builder
      # with no GPU and no driver. Only opencl/cuda need it; -Dmetal is a meson
      # feature set to `enabled`, which already fails loudly at configure time.
      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        bin="$out/bin/lc0"
        out_txt=$(printf 'uci\nquit\n' | "$bin" 2>/dev/null | tr -d '\r')
        echo "$out_txt" | grep -q uciok || {
          echo "FAIL: lc0 did not answer 'uciok' to a uci handshake" >&2
          echo "$out_txt" >&2
          exit 1
        }
        echo "ok: lc0 speaks UCI"
      '' + lib.optionalString (expectBackend != null) ''
        backends=$(echo "$out_txt" | grep 'option name Backend type' || true)
        case " $backends " in
          *" var ${expectBackend} "*)
            echo "ok: '${expectBackend}' backend is compiled in" ;;
          *)
            echo "FAIL: this is lc0-${toString variant}, but '${expectBackend}' is not among its backends." >&2
            echo "meson's probe for it failed and the backend was silently dropped." >&2
            echo "got: $backends" >&2
            exit 1 ;;
        esac
      '' + ''
        runHook postInstallCheck
      '';

      meta = with lib; {
        description = "Leela Chess Zero, a neural-network MCTS engine"
          + (if variant == null then " (CPU)" else " (${variant} backend)")
          + ", bring your own network";
        homepage = "https://lczero.org";
        license = licenses.gpl3Only;
        mainProgram = "lc0";
        inherit platforms;
        maintainers = [ ];
      };
    };
in
{
  lc0 = mkLc0 {
    variant = null;
    backend = { };
    platforms = lib.platforms.unix;
  };
}
# OpenCL ships an ICD loader, and CUDA a toolchain, that only exist on Linux
# here; on macOS the GPU story is Metal, below.
// lib.optionalAttrs stdenv.hostPlatform.isLinux {
  lc0-opencl = mkLc0 {
    variant = "opencl";
    backend = { opencl = true; };
    platforms = lib.platforms.linux;
    expectBackend = "opencl";
    # opencl-clhpp supplies the C++ bindings as CL/opencl.hpp. It is not
    # optional: lc0's src/neural/backends/opencl/OpenCL.h takes CL/opencl.hpp
    # when __has_include finds one and otherwise falls back to its vendored
    # third_party/opencl.hpp, and that vendored copy predates the split of the
    # D3D external-memory enums into the Windows-only part of cl_ext.h. Against
    # the current opencl-headers it fails to compile on
    # CL_EXTERNAL_MEMORY_HANDLE_D3D11_TEXTURE_KHR and friends. Providing the
    # real header keeps the fallback out of the build entirely.
    buildInputs = [ ocl-icd opencl-headers opencl-clhpp ];
    # Both paths have to be spelled out, and the libdir one is the trap: lc0
    # gates the backend on `has_opencl`, which needs BOTH probes to pass, and
    # then compiles a BLAS-only binary in silence when either fails.
    #
    #   opencl_include  defaults to /usr/include, where there is no CL/opencl.h.
    #   opencl_libdirs  defaults to ['/opt/cuda/lib64/', '/usr/local/cuda/lib64/']
    #                   and reaches meson as `cc.find_library('OpenCL', dirs:)`.
    #                   A non-empty `dirs` makes find_library search those
    #                   directories *instead of* the compiler's own search path,
    #                   so ocl-icd being in buildInputs is not enough — without
    #                   this the probe fails and -Dopencl=true is a no-op.
    mesonFlags = [
      "-Dopencl_include=${opencl-headers}/include"
      "-Dopencl_libdirs=${lib.getLib ocl-icd}/lib"
    ];
  };

  lc0-cuda = mkLc0 {
    variant = "cuda";
    backend = { cuda = true; };
    platforms = lib.platforms.linux;
    expectBackend = "cuda";
    nativeBuildInputs = [ cudaPackages.cuda_nvcc ];
    buildInputs = [ cudaPackages.cuda_cudart cudaPackages.libcublas ];
    # Same silent-skip shape as OpenCL: the CUDA backend is gated on
    # cublas/cudart/nvcc all being found, and lc0 drops it without a word
    # otherwise. cudnn_libdirs is the one that bites — it is passed straight to
    # `cc.find_library(dirs:)`, and a non-empty dirs list replaces the default
    # library search path rather than extending it, so the /opt/cuda defaults
    # shadow the store paths that buildInputs put in scope. cudnn_include
    # (the option covers plain CUDA too) defaults to /opt/cuda as well.
    mesonFlags = [
      # cuda_nvcc is in this list for a header, not for the compiler: cudart's
      # driver_types.h includes crt/host_defines.h, and that crt/ tree ships
      # with nvcc rather than cudart. Without it the *C++* half of the backend
      # (layers.cc, compiled by g++, not nvcc) fails to find it.
      "-Dcudnn_include=${lib.getDev cudaPackages.cuda_cudart}/include,${lib.getDev cudaPackages.libcublas}/include,${lib.getDev cudaPackages.cuda_nvcc}/include"
      "-Dcudnn_libdirs=${lib.getLib cudaPackages.cuda_cudart}/lib,${lib.getLib cudaPackages.libcublas}/lib"

      # The CUDA counterpart of -Dnative_arch=false above, and it matters more:
      # native_cuda defaults to true, which passes nvcc -arch=native so the GPU
      # code is emitted only for the card in the build machine. On a builder
      # with no NVIDIA card at all — CI, or any of the machines that would
      # actually cut a release — nvcc cannot detect one, warns, and silently
      # falls back to its default arch, producing a binary that is wrong
      # everywhere on purpose. false selects -arch=all-major, which is the
      # portable, cacheable artifact; an owner who wants their own card's arch
      # can pass -Dcc_cuda= in a local build.
      "-Dnative_cuda=false"
    ];
  };
}
// lib.optionalAttrs stdenv.hostPlatform.isDarwin {
  lc0-metal = mkLc0 {
    variant = "metal";
    backend = { metal = true; };
    platforms = lib.platforms.darwin;
    # Link with LLVM lld. The default cctools ld (ld64 1010.6) dies with
    # SIGTRAP on this link, and bisecting it shows the trigger is the
    # Objective-C++ Metal objects themselves (NetworkGraph.mm,
    # MetalNetworkBuilder.mm) — not the Metal frameworks, which each link fine
    # on their own, and not LTO. lld links the same objects without complaint.
    # Only this variant is affected; the others keep the stdenv linker.
    #
    # The arg has to go on objc/objcpp, not just cpp: the lc0 target mixes C++
    # with Objective-C++, and meson picks the linker — and therefore the
    # <lang>_link_args — from the ObjC++ side, so a lone -Dcpp_link_args is
    # accepted at configure time and then never reaches the link.
    nativeBuildInputs = [ lld ];
    mesonFlags = [
      "-Dcpp_link_args=-fuse-ld=lld"
      "-Dobjc_link_args=-fuse-ld=lld"
      "-Dobjcpp_link_args=-fuse-ld=lld"
    ];
  };
}
