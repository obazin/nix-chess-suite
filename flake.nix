{
  description = "Reproducible UCI chess engines for Linux, macOS and Windows";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  # Advertise the project's binary cache so consumers download the prebuilt,
  # CI-pushed engine binaries instead of compiling ~79 engines from source.
  # Nix asks the user to trust these the first time they use the flake (or
  # applies them automatically for a trusted user). Covers the three
  # CI-built systems: aarch64-darwin, x86_64-linux, aarch64-linux.
  nixConfig = {
    extra-substituters = [ "https://pub-428250a0977d4667937b8ce7e16887ce.r2.dev" ];
    extra-trusted-public-keys = [
      "nix-chess-suite-1:5uNzouWBsIpF0iwdnTgQj2A8ZSdvFFLfV5kkiapqW9U="
    ];
  };

  outputs = { self, nixpkgs }:
    let
      # x86_64-darwin was removed from nixpkgs in 2026-07; Intel Mac is not a
      # supported Nix target any more. Windows binaries are produced by the
      # native GitHub Actions runners, not by pkgsCross, because a meaningful
      # fraction of these hand-rolled Makefiles do not survive mingw.
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      # lc0 is flagged broken on Darwin in nixpkgs, but 0.32.1 builds and
      # passes a UCI handshake on aarch64-darwin — verified directly. The Maia
      # engines depend on it, so the flag is overridden here rather than
      # dropping Maia on macOS. Revisit if an upstream fix lands.
      nixpkgsConfig = {
        problems.handlers.lc0.broken = "ignore";
      };

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system:
          f (import nixpkgs { inherit system; config = nixpkgsConfig; }));
    in
    {
      overlays.default = final: prev: {
        mkEngine = final.callPackage ./lib/mkEngine.nix { };
        chessEngines = import ./engines { pkgs = final; };
      };

      packages = forAllSystems (pkgs:
        let
          lib = nixpkgs.lib;
          mkEngine = pkgs.callPackage ./lib/mkEngine.nix { };
          engines = import ./engines { inherit pkgs mkEngine; };
          # Engines whose meta.platforms includes this system. The x86-only
          # engines (obsidian, gull, igel) drop out here on aarch64 so they
          # neither break `nix flake check` nor the aggregate.
          buildable = lib.filterAttrs
            (_: drv: builtins.elem pkgs.stdenv.hostPlatform.system
              (drv.meta.platforms or [ ]))
            engines;

          # Windows binaries are produced by cross-compiling the very same
          # engine derivations to mingw (UCRT) from the x86_64-linux runner —
          # reusing every patch, net pin and flag rather than reimplementing
          # them. Exposed only on x86_64-linux (the cross build host); each
          # engine that declares x86_64-windows becomes `win-<name>`. The
          # in-sandbox UCI check is dropped for the cross build (it would need
          # wine); CI verifies the .exe compiles and links.
          crossPkgs = pkgs.pkgsCross.mingw-ucrt-x86_64;
          crossEngines = import ./engines {
            pkgs = crossPkgs;
            mkEngine = crossPkgs.callPackage ./lib/mkEngine.nix { };
          };
          winBuildable = lib.filterAttrs
            (_: drv: builtins.elem "x86_64-windows" (drv.meta.platforms or [ ]))
            crossEngines;
          winPackages = lib.mapAttrs'
            (name: drv: lib.nameValuePair "win-${name}"
              (drv.overrideAttrs (_: { doInstallCheck = false; doCheck = false; })))
            winBuildable;

          # An installable bundle: every engine's bin/ merged into one, so
          # `nix profile install` puts every engine on PATH at once (stockfish,
          # fruit, lc0, maia-1500, …). Engine binary names are unique.
          allEngines = pkgs.buildEnv {
            name = "chess-engines-all";
            paths = lib.attrValues buildable;
            ignoreCollisions = true;
          };

          # Native/opt-in variants of the strong tier: built with -march=native
          # (or Rust target-cpu=native) for the CPU that builds them, instead of
          # the portable cached baseline. A consumer opts in per engine
          # (`#stockfish-native`) or with the `native` bundle. These are
          # CPU-specific, so they are ALWAYS built locally and never pushed to /
          # pulled from the shared cache (see lib/mkNative.nix). Not in `checks`,
          # so CI never builds or caches them. lc0 is excluded (it is a wrapper
          # around the nixpkgs meson build). Value is `isRust`.
          mkNative = import ./lib/mkNative.nix;
          strongTier = {
            stockfish = false; berserk = false; obsidian = false;
            plentychess = false; caissa = false; rubichess = false;
            alexandria = false; clover = false; seer = false; stormphrax = false;
            viridithas = true; reckless = true;
          };

          # Profile-guided optimisation, layered on top of `-march=native` for
          # engines whose upstream build ships a PGO target. PGO compiles the
          # engine, runs it to record a profile, then recompiles guided by that
          # profile — a further few percent on top of native codegen. It runs
          # the just-built binary mid-build, which is only sound because native
          # variants are already local-only (built on, and for, this CPU).
          # Each entry is an overrideAttrs function applied after mkNative; only
          # engines listed here get PGO, the rest stay native-only.
          #
          # Stockfish: swap its plain `build` make target for `profile-build`
          # (its own PGO pipeline: instrumented build -> `bench` -> rebuild).
          # With GCC (Linux) this needs no extra tools; with Clang (Darwin) the
          # pipeline shells out to `llvm-profdata` to merge the raw profile, so
          # put the matching llvm on PATH there.
          # llvm-profdata (from the matching llvm) is on PATH only when the
          # stdenv compiler is Clang (Darwin); GCC (Linux) merges .gcda inline
          # and needs no extra tool. Reused by every clang-path PGO entry below.
          llvmForClang = lib.optional pkgs.stdenv.cc.isClang pkgs.llvmPackages.llvm;
          pgoOverrides = {
            # Stockfish: swap `build` for its `profile-build` PGO target.
            stockfish = old: {
              makeFlags = map (f: if f == "build" then "profile-build" else f)
                old.makeFlags;
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ llvmForClang;
            };

            # Berserk: its `pgo` target runs the full cycle, but the makefile
            # selects the gcc/clang PGO path by substring-matching $(CC) — and
            # mkEngine passes CC=cc, which matches neither ("PGO not supported").
            # Rename CC/CXX to gcc/clang (the nix cc-wrapper provides both names
            # and still honours mkNative's -march=native). On Darwin the clang
            # path merges via `$(XCRUN) llvm-profdata`; xcrun isn't in the
            # sandbox, so blank it (XCRUN=) to call llvm-profdata directly. The
            # net is pinned in-tree, so `pgo: download-network` finds it and
            # never curls. Bench (`./berserk bench 13`) uses the embedded net.
            berserk = old: {
              makeFlags = (map
                (f:
                  if f == "all" then "pgo"
                  else if f == "CC=cc" then "CC=${if pkgs.stdenv.cc.isClang then "clang" else "gcc"}"
                  else if f == "CXX=c++" then "CXX=${if pkgs.stdenv.cc.isClang then "clang++" else "g++"}"
                  else f)
                old.makeFlags)
                ++ lib.optional pkgs.stdenv.cc.isClang "XCRUN=";
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ llvmForClang;
            };

            # PlentyChess: standalone derivation with a literal buildPhase (not
            # mkEngine makeFlags), so retarget the make goal in the buildPhase
            # string. `make all` -> `make profile-build` keeps the interpolated
            # EXE=/CXX=/CC=/EVALFILE= args (net stays embedded, no download). The
            # makefile gates its PGO flags on MAKECMDGOALS being exactly
            # `profile-build`, and detects clang-vs-gcc from `$(CXX) --version`.
            plentychess = old: {
              buildPhase = builtins.replaceStrings
                [ "make all" ] [ "make profile-build" ] old.buildPhase;
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ llvmForClang;
            };

            # RubiChess: standalone. The base build deliberately uses the plain
            # `compile` target to avoid the mid-build bench run; for a native,
            # local-only variant that run is exactly what we want, so switch to
            # `profile-build`. Two extra needs: (1) the bench step loads the net
            # from cwd, so drop the pinned net (from the already-built base
            # engine) there — this also satisfies the `net` prerequisite so it
            # never curls; (2) the PGO cycle runs `libclean`, which deletes the
            # pre-placed nixpkgs libz.a and would force a rebuild of the bundled
            # zlib (which no longer compiles against the macOS SDK) — patch
            # libclean to keep the .a. COMP is chosen by uname, matching stdenv.
            rubichess = old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ llvmForClang;
              postPatch = (old.postPatch or "") + ''
                substituteInPlace Makefile \
                  --replace-fail '$(RM) zlib/*.o zlib/*.a' '$(RM) zlib/*.o'
              '';
              buildPhase = ''
                runHook preBuild
                install -Dm644 "${pkgs.zlib.static}/lib/libz.a" zlib/libz.a
                cp ${engines.rubichess}/bin/*.nnue .
                make profile-build \
                  EXE=rubichess \
                  ARCH=${if pkgs.stdenv.hostPlatform.isAarch64 then "armv8" else "x86-64-avx2"} \
                  COMP=${if pkgs.stdenv.cc.isClang then "clang" else "gcc"} \
                  CC="${pkgs.stdenv.cc.targetPrefix}cc" \
                  CXX="${pkgs.stdenv.cc.targetPrefix}c++" \
                  MYCC="${pkgs.stdenv.cc.targetPrefix}cc"
                runHook postBuild
              '';
            };

            # Obsidian: x86-only, so it only ever builds on x86-linux (GCC). Its
            # PGO target is literally named `make` (swap the `nopgo` target for
            # it). The recipe hardcodes g++/gcc with pure GCC PGO
            # (-fprofile-generate="obs_pgo" -> bench -> -fprofile-use), so no
            # llvm-profdata is needed; the net is pre-placed (download-net is a
            # no-op) and embedded via incbin, so bench runs offline.
            obsidian = old: {
              makeFlags = map (f: if f == "nopgo" then "make" else f)
                old.makeFlags;
            };

            # Seer: its `pgo` target does the full cycle with bare GCC
            # -fprofile-generate/-fprofile-use (.gcda, no external tool). But on
            # Clang the same makefile never runs `llvm-profdata merge`, so the
            # profile-use pass has no .profdata and the build fails — and adding
            # llvm doesn't help since nothing calls it. So enable PGO only on
            # GCC (Linux); on Clang (Darwin) leave seer-native native-only (a
            # no-op override). Net is embedded via INCBIN, so bench is offline.
            seer = old:
              if pkgs.stdenv.cc.isClang then { } else {
                makeFlags = map (f: if f == "binary" then "pgo" else f)
                  old.makeFlags;
              };
          };

          nativePackages = lib.mapAttrs'
            (name: isRust:
              let
                native = mkNative isRust engines.${name};
                pgo = if pgoOverrides ? ${name}
                  then native.overrideAttrs pgoOverrides.${name}
                  else native;
              in
              lib.nameValuePair "${name}-native" pgo)
            strongTier;
          # Only the native variants buildable on this system, for the bundle.
          nativeBuildable = lib.filterAttrs
            (_: drv: builtins.elem pkgs.stdenv.hostPlatform.system
              (drv.meta.platforms or [ ]))
            nativePackages;
          nativeBundle = pkgs.buildEnv {
            name = "chess-engines-native";
            paths = lib.attrValues nativeBuildable;
            ignoreCollisions = true;
          };
        in
        engines
        // nativePackages
        // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") winPackages
        // {
          all = allEngines;
          default = allEngines;
          native = nativeBundle;
        });

      # Only the engines buildable on each system — evaluating an x86-gated
      # engine on aarch64 would fail `nix flake check` with "unsupported system".
      checks = forAllSystems (pkgs:
        let
          engines = import ./engines {
            inherit pkgs;
            mkEngine = pkgs.callPackage ./lib/mkEngine.nix { };
          };
        in
        nixpkgs.lib.filterAttrs
          (_: drv: builtins.elem pkgs.stdenv.hostPlatform.system
            (drv.meta.platforms or [ ]))
          engines);

      # `nix run .#update -- --tier strong`, called by the update workflow.
      # Wrapped so nix-update and its helpers are on PATH in a pinned env.
      apps = forAllSystems (pkgs:
        let
          updater = pkgs.writeShellApplication {
            name = "update-engines";
            runtimeInputs = with pkgs; [ nix-update nix jq curl gnused coreutils ];
            text = builtins.readFile ./ci/update.sh;
          };
        in
        {
          update = {
            type = "app";
            program = "${updater}/bin/update-engines";
          };
        });
    };
}
