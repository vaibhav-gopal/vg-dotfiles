#!/usr/bin/env bash
# Bootstrap a NixOS-WSL distro from a fresh clone: host, checkout, .env and the first switch.
# A fresh distro logs in as `nixos`; when the configuration's user differs, the first build is a
# `boot` and the distro must restart before that user exists (the steps are printed). Idempotent.
# Usage: nix/scripts/bootstrap/nixos-wsl.sh [host] [--dry-run] [--switch|--boot]
# tend: vg-dotfiles/Composition/Bootstrap
set -euo pipefail
# shellcheck source=nix/scripts/bootstrap/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BS_ARCHETYPE="nixos-wsl"

# step: build the system and switch to it (boot when the default user changes)
step_system() {
  local out mode="$BS_MODE"
  out="$(bs_build_system "nixosConfigurations.$BS_HOST.config.system.build.toplevel")" || return 1
  if (( BS_DRY_RUN )); then
    bs_info "the system evaluates; would build and apply it ($mode)"
    return 0
  fi
  if [[ "$(readlink -f /run/current-system)" == "$out" ]]; then
    bs_info "already running this system"
    return 0
  fi
  if [[ "$mode" == "auto" ]]; then
    mode="switch"
    [[ "$(id -un)" == "$BS_USERNAME" ]] || mode="boot"
  fi
  # switch exits 4 when a unit (dbus becoming dbus-broker, say) only changes on a restart
  local rc=0
  sudo env NIX_CONFIG="$NIX_CONFIG" nixos-rebuild "$mode" --flake "$BS_FLAKE#$BS_HOST" || rc=$?
  if (( rc == 4 )); then
    bs_warn "some units only change after a restart: \`wsl --terminate <distro>\` from Windows"
  elif (( rc != 0 )); then
    return "$rc"
  fi
  if [[ "$mode" == "boot" ]]; then
    cat <<EOF
  The default user becomes $BS_USERNAME after a restart. From Windows (PowerShell):
    wsl --terminate <distro>
    wsl -d <distro> --user root exit
    wsl --terminate <distro>
  Then open the distro (as $BS_USERNAME), clone the repo to ~/vg-dotfiles and re-run this script.
EOF
  fi
}

bs_parse_args "$@"
bs_steps step_host step_checkout step_env step_system
