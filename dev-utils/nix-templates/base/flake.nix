# flake template for any project: an empty dev shell (and a debug one on top) to fill in, loaded by direnv.
# tend: vg-dotfiles/Dev utils/base
{
  description = "A development environment";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    # follow unstable only for a package that needs it, and say so beside it
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils, ... }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
      pkgs-unstable = import nixpkgs-unstable { inherit system; };

      baseShell = pkgs.mkShell {
        packages = [
          # pkgs.<tool>, or pkgs-unstable.<tool> where 26.05's is too old
        ];
      };
    in {
      # PROJECT DERIVATIONS (nix build)
      packages = {
        # default = ...;
      };

      # CHECKS (nix flake check): builds, linters and tests
      checks = {
        # default = ...;
      };

      # DEV SHELLS (nix develop, or direnv through .envrc)
      devShells = {
        default = baseShell;
        debug = pkgs.mkShell {
          inputsFrom = [ baseShell ];
          packages = [
            # debug tools on top of the base shell
          ];
        };
      };
    }
  );
}
