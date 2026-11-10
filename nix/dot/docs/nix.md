# Nix: finding, trying and keeping packages

Everything on this machine comes from **nixpkgs**, a collection of over 100,000 packages. You
can use any of them without root: a package goes into the shared, read-only `/nix/store` (stored
once, however many people use it) and only appears for you. `nixpkgs` here means the same nixpkgs
the machine itself is built from, so most of what you ask for is already downloaded.

## Which way?

| You want | Use | `dot help` |
| --- | --- | --- |
| a tool once | `dot run <pkg>` (or `nix run nixpkgs#<pkg>`) | |
| a few tools for a while | `dot shell <pkg>...` (or `nix shell`) | |
| a tool at every login | `nix profile add nixpkgs#<pkg>` | |
| a project's toolchain, the same for everyone who clones it | `dot devshell` | `devshells` |
| another distro's userland (apt, Ubuntu), or an app's image | distrobox, podman | `containers` |

## Find a package

```sh
dot find ripgrep                 # same as: nix search nixpkgs ripgrep
```

The first search reads all of nixpkgs (a minute); later ones are quick. A package's name isn't
always its command's (`ripgrep` gives `rg`): `dot find` shows each package's description, and
<https://search.nixos.org/packages> searches by program name too.

## Try one: `nix shell`

```sh
nix shell nixpkgs#htop nixpkgs#jq          # a shell with both; exit and they're gone from PATH
nix shell nixpkgs#ffmpeg --command ffmpeg -i in.mov out.mp4
nix run nixpkgs#cowsay -- hello            # run a package's main program once
```

The older `nix-shell -p htop jq` works too, from the same nixpkgs.

## Keep one: `nix profile`

Your **profile** is your own list of installed packages, on your PATH at every login:

```sh
nix profile add nixpkgs#ripgrep nixpkgs#btop    # (`nix profile install` is the old name)
nix profile list                                # what's in it
nix profile remove ripgrep
nix profile upgrade --all                       # newer versions, once the machine's nixpkgs moves on
nix profile rollback                            # undo the last change
```

Every change is a new generation (`nix profile history`), so a rollback is always there. Old
generations keep their packages in the store until you drop them: `nix profile wipe-history`.

Skip `nix-env -i`: it's the old way, slow, and doesn't mix well with `nix profile`.

## A newer or older version

`nixpkgs` follows the machine (NixOS 26.05). For something newer, or a fixed point in time:

```sh
nix shell nixpkgs/nixos-unstable#<pkg>          # this week's nixpkgs
nix shell github:NixOS/nixpkgs/<commit>#<pkg>   # exactly that commit
```

Either downloads that nixpkgs first, and a package missing from the binary cache is built from
source, which can take a long time. For a project, pin the version in its dev shell instead.

## Unfree packages

Some packages (CUDA, a few drivers and apps) have licenses that need opting in. They fail with
"has an unfree license"; allow it for that one command:

```sh
NIXPKGS_ALLOW_UNFREE=1 nix shell --impure nixpkgs#<pkg>
```

## Python packages and prebuilt binaries

Don't install Python libraries with `nix profile`: they won't be seen by each other or by your
project's Python. Use a dev shell (`dot devshell python`), whose `.venv` takes `uv pip install`.

Linux programs built elsewhere (a downloaded binary, a wheel's extension) expect libraries in
places NixOS doesn't have them. On the servers, nix-ld fills that in for most of them; when one
still won't start, a dev shell with the library, or a distrobox, will run it.

## What needs the admin

You can't use sudo, change the system or run system services. Ask the admin for something every
user should have, a service that runs without you, or access to a device.
