# Dev-shell layers

`dot devshell <layer>...` writes one `flake.nix` from these layers: the ones named, the ones they
require, and `base`, in that order, each layer's lines under a comment naming it. The flake is
self-contained (nixpkgs only), so it's the project's to edit and keep in git.

A layer is a folder of plain files, any of them optional:

| File | Holds | Lands in |
|---|---|---|
| `about` | one line: what the layer is for | `dot devshell`'s list |
| `requires` | other layers' names, one per line | added before this one |
| `packages` | nixpkgs attributes, one per line (`python312`, `stdenv.cc.cc.lib`) | `packages = with pkgs; [ ... ]` |
| `libs` | libraries prebuilt binaries and wheels expect from the system | `LD_LIBRARY_PATH` |
| `env` | Nix attribute lines (`NAME = "value";`; `pkgs` is in scope) | the `mkShell` attributes |
| `hook` | shell lines, run on entering | `shellHook` |

`hook` lands inside a Nix `''` string: write `''${` for a shell `${`, or avoid it.
