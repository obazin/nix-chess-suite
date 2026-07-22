{
  description = "Reproducible UCI chess engines for Linux, macOS and Windows";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
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
          mkEngine = pkgs.callPackage ./lib/mkEngine.nix { };
          engines = import ./engines { inherit pkgs mkEngine; };
          # Engines whose meta.platforms includes this system. The x86-only
          # engines (obsidian, gull, igel) drop out here on aarch64 so they
          # neither break `nix flake check` nor the aggregate.
          buildable = nixpkgs.lib.filterAttrs
            (_: drv: builtins.elem pkgs.stdenv.hostPlatform.system
              (drv.meta.platforms or [ ]))
            engines;
        in
        engines // {
          # Everything that builds on this system, for CI to hammer at once.
          default = pkgs.linkFarm "chess-engines" (
            nixpkgs.lib.mapAttrsToList (name: drv: { inherit name; path = drv; })
              buildable
          );
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
