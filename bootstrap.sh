#!/usr/bin/env bash
# Bring this machine up to its configuration after a fresh clone: picks the archetype (NixOS,
# NixOS-WSL or nix-darwin) and runs its idempotent bootstrap in nix/scripts/bootstrap/.
# Usage: ./bootstrap.sh [host] [options]   (./bootstrap.sh --help for the options)
# tend: vg-dotfiles/Composition/Bootstrap
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nix/scripts/bootstrap"

if [[ "$(uname -s)" == "Darwin" ]]; then
  archetype="nix-darwin"
elif [[ -n "${WSL_DISTRO_NAME:-}" || -e /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
  archetype="nixos-wsl"
elif [[ -e /etc/NIXOS ]]; then
  archetype="nixos"
else
  echo "error: not NixOS, NixOS-WSL or macOS; nothing here bootstraps this system" >&2
  exit 1
fi

exec bash "$dir/$archetype.sh" "$@"
