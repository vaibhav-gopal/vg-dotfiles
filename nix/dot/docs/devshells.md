# Dev shells: a project's tools, without installing anything

A **dev shell** is a project's toolchain (compilers, Python, libraries) described in a `flake.nix`
next to the code. `nix develop` drops you into it; leave and it's gone. Everyone who clones the
project gets exactly the same versions, and nothing touches the rest of the machine.

## Start one

A shell is put together from **layers**: `dot devshell` lists them. Name the ones the project
needs and you get one `flake.nix` with all of them (a layer brings what it needs: `tenstorrent`
brings `python`):

```sh
cd ~/projects/my-experiment
git init                              # a flake only sees files git knows about
dot devshell python tenstorrent       # or: cpp, rust, node, ... any mix
git add flake.nix .envrc .gitignore
nix develop                           # enter it (the first time downloads what it needs)
```

The flake is the project's: add packages to its `packages = with pkgs; [ ... ];` list (find names
with `dot find <word>`) and run `nix develop` again. To add a layer later, `dot devshell --print
<layers>` prints a fresh flake to copy the parts you need from.

## Enter it automatically

`direnv` is set up for you: with the `.envrc` dot devshell wrote (`use flake`), run `direnv allow`
once and the shell loads whenever you `cd` into the folder.

## Python projects

The `python` layer gives Python 3.12 and uv, and makes a `.venv` in the project that's active
in the shell: `uv pip install -r requirements.txt` (or `uv add <pkg>` with a `pyproject.toml`).
Prebuilt wheels work: the shell puts the C++ runtime they expect on `LD_LIBRARY_PATH`.

The `tenstorrent` layer adds TT-NN (`ttnn`) to that venv; `dot help tenstorrent` for the card.

## In a Slurm job

Run the command through the shell, so the job gets the same tools:

```sh
srun -c 8 --mem=16G nix develop --command python train.py
```

(`dot help slurm` for jobs.)

## One-off tools

Not worth a flake? `dot shell <pkg>...` opens a shell with them; `dot run <pkg>` runs one once.
To keep one at every login, `nix profile add nixpkgs#<pkg>`: `dot help nix` for all of these.
