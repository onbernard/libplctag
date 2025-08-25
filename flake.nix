{
  description = "libplctag allyourcodebase flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zls = {
      url = "github:zigtools/zls?ref=0.15.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {self, ...}:
    with inputs;
      flake-utils.lib.eachDefaultSystem (
        system: let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [zig-overlay.overlays.default];
          };
        in {
          devShell = pkgs.mkShell {
            packages = [
              # pkgs.zls
              # pkgs.zig
              zls.inputs.zig-overlay.packages.${system}.default
              zls.packages.${system}.zls
            ];
          };
        }
      );
}
