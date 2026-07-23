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
          nativePackages = lib.mapAttrs'
            (name: isRust: lib.nameValuePair "${name}-native"
              (mkNative isRust engines.${name}))
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
