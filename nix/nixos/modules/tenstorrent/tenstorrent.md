# The Tenstorrent card on this machine

One **Blackhole p150a**. The driver and the system tools are installed for everyone; the SDK
(TT-NN / TT-Metalium) goes into each project, so every project picks its own version.

## What's installed

| | |
|---|---|
| Driver | tt-kmd (the `tenstorrent` kernel module), the card at `/dev/tenstorrent/0` |
| Hugepages | 1 GiB pages at `/dev/hugepages-1G`, which the SDK's host runtime maps |
| Tools | `tt-smi` (status, telemetry, reset), `tt-burnin` (stress test), `tt-system-tools` |
| SDK | not system-wide: `ttnn` from PyPI, in a project venv (below) |

`tt-smi` here is nixpkgs' (3.0.x). A newer one runs without installing anything:
`nix shell nixpkgs#uv -c uvx tt-smi` (inside a job, as below).

## Getting the card

Where Slurm runs, the card is only open inside a job that holds it, so nobody's run is disturbed:

```sh
srun --gres=tt:1 -c 8 --mem=16G --pty bash      # a shell with the card
tt-smi                                          # in it: the card, its firmware, temperatures
```

or a batch script with `#SBATCH --gres=tt:1` (`dot help slurm`). When the job ends, Slurm takes
the card back and clears your hugepage files.

## The SDK: TT-NN in a project

```sh
mkdir -p ~/projects/hello-tt && cd ~/projects/hello-tt && git init
dot devshell python tenstorrent       # a flake with Python 3.12, uv and a .venv
git add -A && nix develop             # first time: installs ttnn into .venv
srun --gres=tt:1 -c 8 --mem=16G --pty nix develop --command python
```

```python
import ttnn, torch                     # torch: `uv pip install torch` in the shell first
device = ttnn.open_device(device_id=0)
a = ttnn.from_torch(torch.rand(32, 32), layout=ttnn.TILE_LAYOUT, device=device)
print(ttnn.to_torch(ttnn.add(a, a)))
ttnn.close_device(device)
```

**Versions have to line up:** each ttnn release is built for a firmware version (tt-metal's
`INSTALLING.md` for that release lists it). Pin the one that matches the card,
`uv pip install ttnn==<version>`, and check the card's firmware with `tt-smi` (`fw_bundle_version`).
If they don't match, `open_device` fails or misbehaves: ask the admin to update the firmware, or use
an older ttnn.

## C++ (TT-Metalium)

Build tt-metal from source in a project shell (`dot devshell cpp python`, then tt-metal's own build
instructions), or use the headers and libraries in nixpkgs' `tt-metal` package, which is older
than the PyPI wheels. Building it is heavy: do it in a job (`srun -c 16 --mem=32G ...`).

## In a container

A container gets the card the same way, inside a job: `podman run --device /dev/tenstorrent/0 ...`.
Tenstorrent's own images (`ghcr.io/tenstorrent/tt-metal/...`) work like this.

## If the card misbehaves

- `tt-smi -r` (in a job) resets it; then try again.
- Still stuck, or `tt-smi` doesn't list it: tell the admin (a reboot, or the firmware).
