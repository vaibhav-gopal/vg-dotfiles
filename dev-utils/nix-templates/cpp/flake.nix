# flake template for a C/C++ project: CMake and Ninja, the package built with its CTest tests as the flake
# check, plus a dev shell with clangd (compile_commands.json is exported) and a debugger.
# tend: vg-dotfiles/Dev utils/cpp
{
  description = "A C/C++ project";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      package = pkgs.stdenv.mkDerivation {
        pname = "hello";
        version = "0.1.0";
        # the build's inputs only, so other edits don't rebuild
        src = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [ ./CMakeLists.txt ./include ./src ./tests ];
        };
        nativeBuildInputs = [ pkgs.cmake pkgs.ninja ];
        doCheck = true; # CTest, through the build's `test` target
      };
    in {
      packages.default = package;

      # nix flake check: the build, with its tests
      checks.default = package;

      devShells.default = pkgs.mkShell {
        inputsFrom = [ package ];
        packages = [ pkgs.clang-tools ] # clangd, clang-format, clang-tidy
          ++ lib.optional pkgs.stdenv.isLinux pkgs.gdb
          ++ lib.optional pkgs.stdenv.isDarwin pkgs.lldb;
      };
    }
  );
}
