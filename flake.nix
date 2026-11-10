# root flake: `dot` (nix/dot), the dev shell for working on this repo (dot, and shellcheck for the
# scripts), and the flake templates new projects start from. A fresh machine starts here:
# `nix run github:vaibhav-gopal/vg-dotfiles#dot -- bootstrap <host>`.
# tend: vg-dotfiles/Composition
{
  description = "Starter environment for vg-dotfiles";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }: (flake-utils.lib.eachDefaultSystem (system:
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
  )) // {
    # starters for new projects: `nix flake init -t ~/vg-dotfiles#<name>` in an empty git repo
    # (dev-utils/nix-templates; nix/scripts/tests/templates.test.sh checks each one starts a project that passes)
    # tend: vg-dotfiles/Dev utils
    templates = let
      template = name: description: {
        path = ./dev-utils/nix-templates + "/${name}";
        inherit description;
        welcomeText = ''
          # ${description}
          `git add -A`, then `nix flake check` and `nix run`; `direnv allow` (or `nix develop`) for the dev shell.
          Rename `hello` to the project's name where the files say so.
        '';
      };
    in {
      base = template "base" "A dev shell to fill in";
      rust = template "rust" "A Rust project built with crane: clippy, fmt and tests as flake checks";
      cpp = template "cpp" "A C/C++ project with CMake and Ninja, its CTest tests as the flake check";
      bun = template "bun" "A TypeScript project on Bun, bun test as the flake check";
      python = template "python" "A Python project from uv.lock with uv2nix, pytest as the flake check";
      default = self.templates.base;
    };
  };
}
