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
    extra-substituters = [ "https://nix-chess-suite.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-chess-suite.cachix.org-1:TMsUd9aoIz7tpCCs/Tiu2aDIpRParToEj9QxZAECO4Y="
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
        in
        engines
        // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") winPackages
        // {
          all = allEngines;
          default = allEngines;
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
