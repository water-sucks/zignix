{
  description = "Zig bindings to Nix package manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    nix.url = "github:nixos/nix";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-parts,
    ...
  } @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [];

      systems = nixpkgs.lib.systems.flakeExposed;

      perSystem = {
        pkgs,
        lib,
        system,
        ...
      }: let
        inherit (pkgs) zig pkg-config;
        nixPackage = inputs.nix.packages.${system}.nix;
      in {
        devShells.default = pkgs.mkShell {
          name = "nixos-shell";
          nativeBuildInputs = [
            zig
            pkg-config
          ];
          buildInputs = [
            nixPackage.dev
          ];

          ZIG_DOCS = "${zig}/doc/langref.html";
        };
      };
    };
}
