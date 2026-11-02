# root dev shell for working on this repo (just, and shellcheck for the scripts), built on flake-utils,
# and the flake templates new projects start from.
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

        baseShell = pkgs.mkShellNoCC {
            packages = [
                pkgs.just
                pkgs.shellcheck
            ];
        };
    in {
        devShells.default = baseShell;
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
