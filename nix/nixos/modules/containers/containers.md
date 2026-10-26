# Containers on this machine

Two tools, both rootless: what you run is yours alone, stored in `~/.local/share/containers`, and
none of it needs sudo on the host.

- **distrobox**: another Linux distribution's userland that feels like part of this one. Your home
  directory, your files and your terminal carry over; inside it you have that distro's package
  manager and `sudo` (root inside is really just you).
- **podman**: run an application's container image. `docker` is an alias for it, so most Docker
  instructions work as written.

## Another distro: distrobox

```sh
distrobox create --name ubuntu --image ubuntu:24.04
distrobox enter ubuntu          # a shell in Ubuntu
sudo apt update && sudo apt install build-essential    # inside: apt and sudo work
exit
distrobox list                  # your boxes
distrobox rm ubuntu             # remove one (your home directory stays)
```

Good for tools that only ship as `.deb` or expect Ubuntu paths. Prefer a Nix dev shell
(`dot help devshells`) when the tools are in nixpkgs: it's reproducible and lives in the project.

Run one command inside without entering: `distrobox enter ubuntu -- make`. Export an app or a
binary from the box to your normal shell: `distrobox-export --bin /usr/bin/<tool>` (inside the box).

## An application's image: podman

```sh
podman run --rm -it docker.io/library/python:3.12 python     # interactive, removed on exit
podman run -d --name db -p 5432:5432 -e POSTGRES_PASSWORD=dev docker.io/library/postgres:16
podman ps / podman logs db / podman stop db / podman rm db
podman images / podman system df / podman system prune        # what's stored, and clearing it
```

`podman-compose up` reads a `docker-compose.yml`. Use full image names
(`docker.io/library/...`); short names may ask which registry you meant.

**Ports:** a published port (`-p 8080:80`) is on this machine only (localhost, and the ports the
firewall leaves open). Reach it from your laptop with an SSH tunnel: `ssh -L 8080:localhost:8080 <this host>`.

## Keeping things running after you log out

Containers and user services stop when your last session ends, unless lingering is on for you
(the admin turns it on: `profiles.users.<you>.linger`). With it, `podman run -d` containers and
`systemctl --user` services keep running.

## In a Slurm job

Containers run in jobs too (`srun -c 8 --mem=16G podman run ...`), and get the job's cores and
memory. A container that needs the Tenstorrent card must run inside a job that holds it
(`--gres=tt:1`) and be given the device: `--device /dev/tenstorrent/0`.

## On a shared machine

Your containers follow the same rules as you: they reach the internet, not the machine owner's
network or tailnet, and can't see other people's containers.
