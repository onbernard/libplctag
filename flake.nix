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
          buildScript = pkgs.writeShellScriptBin "zig-build-all" ''
            set -euo pipefail
            echo "▶ Building for x86_64-linux (gnu)..."
            zig build -Dtarget=x86_64-linux-gnu -Dbuild-examples=true -Dbuild-ab-server=true -Doptimize=ReleaseFast

            echo "▶ Building for Windows (gnu)..."
            zig build -Dtarget=x86_64-windows-gnu -Dbuild-examples=true -Dbuild-ab-server -Doptimize=ReleaseFast
            echo "✅ All builds finished."
          '';
        in {
          devShell = pkgs.mkShell {
            packages = [
              # pkgs.zls
              # pkgs.zig
              zls.inputs.zig-overlay.packages.${system}.default
              zls.packages.${system}.zls
              pkgs.dprint
              pkgs.libmodbus
              buildScript
            ];
          };
        }
      );
}
