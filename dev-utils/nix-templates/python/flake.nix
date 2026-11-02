# flake template for a Python project: a uv workspace built with uv2nix / pyproject.nix (the package as a
# virtualenv, pytest as the flake check), plus a dev shell with the project installed editable.
# tend: vg-dotfiles/Dev utils/python
#
# uv owns the dependencies (`uv add`, `uv lock`; commit uv.lock); nix builds from uv.lock and never lets uv
# install anything itself.
{
  description = "A Python project";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, pyproject-nix, uv2nix, pyproject-build-systems, ... }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # pyproject.toml and uv.lock
      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      python = lib.head (pyproject-nix.lib.util.filterPythonInterpreters {
        inherit (workspace) requires-python;
        inherit (pkgs) pythonInterpreters;
      });

      # every locked package, from wheels where there are some
      pythonSet = (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope (
        lib.composeManyExtensions [
          pyproject-build-systems.overlays.wheel
          (workspace.mkPyprojectOverlay { sourcePreference = "wheel"; })
        ]
      );

      # the same, with this project installed editable from the checkout (for the dev shell)
      editablePythonSet = pythonSet.overrideScope (
        lib.composeManyExtensions [
          (workspace.mkEditablePyprojectOverlay { root = "$REPO_ROOT"; })
          (final: prev: {
            hello = prev.hello.overrideAttrs (old: {
              # an editable install needs `editables` to build
              nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem { editables = [ ]; };
            });
          })
        ]
      );

      package = pythonSet.mkVirtualEnv "hello-env" workspace.deps.default;
      testEnv = pythonSet.mkVirtualEnv "hello-test-env" workspace.deps.all;
    in {
      # the project and its runtime dependencies; bin/hello is its entry point
      packages.default = package;

      # nix flake check: the tests, against the installed (not editable) package
      checks.test = pkgs.runCommand "hello-test" { nativeBuildInputs = [ testEnv ]; } ''
        cp -r ${./tests} tests && chmod -R u+w tests
        export PYTHONDONTWRITEBYTECODE=1
        pytest -p no:cacheprovider tests
        touch "$out"
      '';

      devShells.default = pkgs.mkShell {
        packages = [
          (editablePythonSet.mkVirtualEnv "hello-dev-env" workspace.deps.all)
          pkgs.uv
        ];
        env = {
          UV_NO_SYNC = "1"; # uv2nix owns the virtualenv
          UV_PYTHON = editablePythonSet.python.interpreter;
          UV_PYTHON_DOWNLOADS = "never"; # python comes from nix
        };
        shellHook = ''
          unset PYTHONPATH
          export REPO_ROOT=$(git rev-parse --show-toplevel)
        '';
      };
    }
  );
}
