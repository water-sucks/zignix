{
  description = "Zig bindings to Nix package manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    nix.url = "github:nixos/nix";

    zig-overlay.url = "github:mitchellh/zig-overlay";

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
        zigPackage = inputs.zig-overlay.packages.${system}."0.12.0";
        nixPackage = inputs.nix.packages.${system}.nix;
      in {
        devShells.default = pkgs.mkShell {
          name = "nixos-shell";
          packages = [
            pkgs.alejandra
            pkgs.zls
          ];
          nativeBuildInputs = [
            zigPackage
            pkgs.pkg-config
          ];
          buildInputs = [
            nixPackage.dev
          ];

          ZIG_DOCS = "${zigPackage}/doc/langref.html";
          ZIG_STD_DOCS = "${zigPackage}/doc/std/index.html";
        };
      };
    };
}
