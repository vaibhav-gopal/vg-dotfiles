# flake template for a Rust project: built with crane (dependencies once, then the package, clippy, fmt
# and the tests as flake checks over the same artifacts), plus its dev shell.
# tend: vg-dotfiles/Dev utils/rust
{
  description = "A Rust project";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
    crane.url = "github:ipetkov/crane"; # needs nixpkgs 26.05 or later
  };

  outputs = { self, nixpkgs, flake-utils, crane, ... }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };
      craneLib = crane.mkLib pkgs;

      # Cargo.toml, Cargo.lock and the Rust sources only, so other edits don't rebuild
      src = craneLib.cleanCargoSource ./.;
      commonArgs = {
        inherit src;
        strictDeps = true;
        # a workspace whose root Cargo.toml has no [package] sets pname and version here
      };

      # the dependencies, built once and reused by every derivation below
      cargoArtifacts = craneLib.buildDepsOnly commonArgs;

      package = craneLib.buildPackage (commonArgs // {
        inherit cargoArtifacts;
        doCheck = false; # the tests are their own check
      });
    in {
      packages.default = package;

      # nix flake check: everything a change must pass
      checks = {
        inherit package;
        clippy = craneLib.cargoClippy (commonArgs // {
          inherit cargoArtifacts;
          cargoClippyExtraArgs = "--all-targets -- --deny warnings";
        });
        fmt = craneLib.cargoFmt { inherit src; };
        test = craneLib.cargoTest (commonArgs // { inherit cargoArtifacts; });
      };

      # cargo, rustc, clippy and rustfmt from the same toolchain as the build, and what the checks need
      devShells.default = craneLib.devShell {
        checks = self.checks.${system};
        packages = [ pkgs.rust-analyzer ];
        RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
      };
    }
  );
}
