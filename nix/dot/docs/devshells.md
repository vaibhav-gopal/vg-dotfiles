# Dev shells: a project's tools, without installing anything

A **dev shell** is a project's toolchain (compilers, Python, libraries) described in a `flake.nix`
next to the code. `nix develop` drops you into it; leave and it's gone. Everyone who clones the
project gets exactly the same versions, and nothing touches the rest of the machine.

## Start one

```sh
cd ~/projects/my-experiment
git init                     # a flake only sees files git knows about
dot devshell                 # lists the templates
dot devshell base            # a plain shell: add the packages you need
git add flake.nix .envrc
nix develop                  # enter it (the first time downloads what it needs)
```

Edit the `packages = [ ... ];` list in `flake.nix` with what the project needs, e.g.
`pkgs.python3 pkgs.uv pkgs.cmake pkgs.ninja`, and run `nix develop` again. Find package names with
`dot find <word>`.

## Enter it automatically

`direnv` is set up for you: with the `.envrc` the template wrote (`use flake`), run `direnv allow`
once and the shell loads whenever you `cd` into the folder.

## Python projects

`dot devshell python` is a uv workspace (uv2nix). For something quicker, a `base` shell with
`pkgs.python3 pkgs.uv`, then `uv venv && uv pip install -r requirements.txt` inside the project, works
too: prebuilt wheels run here.

## In a Slurm job

Run the command through the shell, so the job gets the same tools:

```sh
srun -c 8 --mem=16G nix develop --command python train.py
```

(`dot help slurm` for jobs.)

## One-off tools

Not worth a flake? `dot shell <pkg>...` opens a shell with them; `dot run <pkg>` runs one once.
To keep a tool across logins, `nix profile install nixpkgs#<pkg>` installs it into your own profile
(only you see it; `nix profile list` / `nix profile remove`).
