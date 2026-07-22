# Build a single engine file without registering it in engines/default.nix.
# Lets several engines be developed in parallel without contending on the
# registry.
#
#   nix build --impure --expr 'import ./test-engine.nix { engine = "fruit"; }'
#
{ engine
, system ? builtins.currentSystem
}:

let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  nixpkgsNode = lock.nodes.${lock.nodes.${lock.root}.inputs.nixpkgs}.locked;

  pkgs = import
    (builtins.fetchTarball {
      url = "https://github.com/${nixpkgsNode.owner}/${nixpkgsNode.repo}/archive/${nixpkgsNode.rev}.tar.gz";
      sha256 = nixpkgsNode.narHash;
    })
    {
      inherit system;
      # Keep in sync with nixpkgsConfig in flake.nix.
      config.problems.handlers.lc0.broken = "ignore";
    };

  mkEngine = pkgs.callPackage ./lib/mkEngine.nix { };
in
pkgs.callPackage (./engines + "/${engine}.nix") { inherit mkEngine; }
