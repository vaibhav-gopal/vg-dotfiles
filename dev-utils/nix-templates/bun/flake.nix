# flake template for a TypeScript project on Bun: `bun test` as the flake check, the program as a package
# that runs its sources with bun, plus its dev shell.
# tend: vg-dotfiles/Dev utils/bun
#
# It starts with no dependencies, so the check runs offline in the sandbox. Once package.json has some,
# commit bun.lock and build node_modules from it as a fixed-output derivation (bun2nix, or
# `bun install --frozen-lockfile` with an outputHash), then put it beside the sources in `check` and `package`.
{
  description = "A TypeScript project on Bun";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # the project's inputs only, so other edits don't rebuild
      src = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [ ./package.json ./tsconfig.json ./src ];
      };

      package = pkgs.writeShellApplication {
        name = "hello";
        runtimeInputs = [ pkgs.bun ];
        text = ''exec bun run ${src}/src/index.ts "$@"'';
      };
    in {
      packages.default = package;

      # nix flake check: the tests, with bun's caches kept inside the build
      checks.test = pkgs.runCommand "hello-test" { nativeBuildInputs = [ pkgs.bun ]; } ''
        cp -r ${src} work && chmod -R u+w work && cd work
        export HOME="$TMPDIR" BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
        bun test
        touch "$out"
      '';

      devShells.default = pkgs.mkShell {
        packages = [ pkgs.bun pkgs.typescript-language-server ];
      };
    }
  );
}
