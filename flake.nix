{
  description = "Zig bindings to Nix package manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    nix.url = "github:nixos/nix/2.30.2";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    flake-parts,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [];

      systems = nixpkgs.lib.systems.flakeExposed;

      perSystem = {
        pkgs,
        system,
        ...
      }: let
        inherit (pkgs) zig pkg-config;
        nixPackage = inputs.nix.packages.${system}.nix;
      in {
        devShells.default = pkgs.mkShell {
          name = "zignix-shell";

          nativeBuildInputs = [
            zig
            pkg-config
          ];

          buildInputs = [
            nixPackage.dev
          ];
        };
      };
    };
}
