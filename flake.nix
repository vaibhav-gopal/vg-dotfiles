# root flake: `dot` (nix/dot), and the dev shell for working on this repo (dot, and shellcheck for the
# scripts). A fresh machine starts here: `nix run github:vaibhav-gopal/vg-dotfiles#dot -- bootstrap <host>`.
# tend: vg-dotfiles/Composition
{
  description = "Starter environment for vg-dotfiles";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }: flake-utils.lib.eachDefaultSystem (system:
    let
        pkgs = import nixpkgs { inherit system; };
        dot = profile: pkgs.callPackage ./nix/dot/package.nix { inherit profile; };
    in {
        packages = {
            dot = dot "admin"; # the checkout is found from where it runs (or ~/vg-dotfiles)
            dot-standard = dot "standard";
            default = self.packages.${system}.dot;
        };

        devShells.default = pkgs.mkShellNoCC {
            packages = [
                self.packages.${system}.dot
                pkgs.shellcheck
            ];
        };
    }
  );
}
