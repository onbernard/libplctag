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
          buildScript = pkgs.writeShellScriptBin "build-all" ''
            set -euo pipefail
            echo "▶ Building for x86_64-linux..."
            zig build -Dtarget=x86_64-linux -Dbuild-examples=true -Dbuild-ab-server=true -Dbuild-modbus-server=true -Doptimize=ReleaseFast

            echo "▶ Building for x86-linux..."
            zig build -Dtarget=x86-linux -Dbuild-examples=true -Dbuild-ab-server=true -Dbuild-modbus-server=false -Doptimize=ReleaseFast

            echo "▶ Building for x86_64-macos..."
            zig build -Dtarget=x86_64-macos -Dbuild-examples=true -Dbuild-ab-server=true -Dbuild-modbus-server=false -Doptimize=ReleaseFast

            echo "▶ Building for aarch64-macos..."
            zig build -Dtarget=aarch64-macos -Dbuild-examples=true -Dbuild-ab-server=true -Dbuild-modbus-server=false -Doptimize=ReleaseFast

            echo "▶ Building for Windows..."
            zig build -Dtarget=x86_64-windows -Dbuild-examples=true -Dbuild-ab-server -Dbuild-modbus-server=true -Doptimize=ReleaseFast
            echo "✅ All builds finished."
          '';
          cleanScript = pkgs.writeShellScriptBin "clean-all" ''
            set -euo pipefail
            echo "▶ Clearing .zig-cache..."
            rm -r .zig-cache

            echo "▶ Clearing zig-out..."
            rm -r zig-out
            echo "✅ All cleared."
          '';
        in {
          devShell = pkgs.mkShell {
            LIBRARY_PATH = pkgs.lib.makeLibraryPath [
              pkgs.libmodbus
            ];
            packages = [
              # pkgs.zls
              # pkgs.zig
              zls.inputs.zig-overlay.packages.${system}.default
              zls.packages.${system}.zls
              pkgs.dprint
              pkgs.libmodbus
              pkgs.pkg-config
              buildScript
              cleanScript
            ];
            shellHook = ''
              export ZIG_GLOBAL_ARGS="$(
                pkg-config --cflags --libs libmodbus
              )"
            '';
          };
        }
      );
}
