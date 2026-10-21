#!/usr/bin/env bash
# Bootstrap a bare-metal NixOS machine from a fresh clone: host, checkout, .env, the machine's
# hardware-configuration.nix, the first build (boot when the kernel changes, else switch), and
# optionally the tailnet login. Idempotent: re-run it after the reboot to finish what is left.
# Usage: nix/scripts/bootstrap/nixos.sh [host] [--dry-run] [--switch|--boot] [--with-tailscale] [--regen-hardware]
# tend: vg-dotfiles/Composition/Bootstrap
set -euo pipefail
# shellcheck source=nix/scripts/bootstrap/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BS_ARCHETYPE="nixos"

# Where the installer left this machine's hardware config (overridden in tests)
BS_ETC_NIXOS="${BS_ETC_NIXOS:-/etc/nixos}"

# This machine's hardware config: the installer's copy, else freshly generated
bs_machine_hardware() {
  if [[ -f "$BS_ETC_NIXOS/hardware-configuration.nix" ]]; then
    cat "$BS_ETC_NIXOS/hardware-configuration.nix"
  else
    nixos-generate-config --show-hardware-config 2>/dev/null
  fi
}

# step: the host's folder has this machine's hardware-configuration.nix, and git tracks it (flakes
# only see tracked files). An existing one that differs is kept unless --regen-hardware.
step_hardware() {
  local dir="$BS_FLAKE/nixos/$BS_HOST" target machine
  target="$dir/hardware-configuration.nix"
  [[ -f "$dir/default.nix" ]] || bs_die "no nix/nixos/$BS_HOST/default.nix: add the host's folder first (README, Adding a machine)"
  machine="$(bs_machine_hardware)" || true
  if [[ -f "$target" ]]; then
    if [[ -n "$machine" && "$(cat "$target")" != "$machine" ]]; then
      if (( ! BS_REGEN_HARDWARE )); then
        bs_warn "the repo's hardware-configuration.nix differs from this machine's; keeping the repo's (--regen-hardware replaces it)"
      else
        bs_run cp "$target" "$target.bak"
        (( BS_DRY_RUN )) || printf '%s\n' "$machine" >"$target"
        bs_info "replaced it with this machine's (old one in hardware-configuration.nix.bak)"
      fi
    else
      bs_info "hardware-configuration.nix in place"
    fi
  else
    [[ -n "$machine" ]] || bs_die "no $BS_ETC_NIXOS/hardware-configuration.nix and nixos-generate-config failed"
    if (( BS_DRY_RUN )); then
      bs_info "would copy this machine's hardware-configuration.nix into nix/nixos/$BS_HOST/"
    else
      printf '%s\n' "$machine" >"$target"
      bs_info "copied this machine's hardware-configuration.nix into nix/nixos/$BS_HOST/"
    fi
  fi
  if [[ -f "$target" ]] && ! git -C "$BS_ROOT" ls-files --error-unmatch "$target" >/dev/null 2>&1; then
    bs_run git -C "$BS_ROOT" add "$target" || return 1
    bs_info "staged it in git (commit and push it from here, or send it over)"
  fi
}

# step: build the system, then apply it: boot (and reboot) when the kernel changes, else switch
step_system() {
  local out mode="$BS_MODE"
  if (( BS_DRY_RUN )) && ! git -C "$BS_ROOT" ls-files --error-unmatch "$BS_FLAKE/nixos/$BS_HOST/hardware-configuration.nix" >/dev/null 2>&1; then
    bs_info "evaluates once the hardware config is in git (a real run copies it first)"
    return 0
  fi
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
    [[ "$(readlink -f "$out/kernel")" == "$(readlink -f /run/booted-system/kernel)" ]] || mode="boot"
  fi
  sudo env NIX_CONFIG="$NIX_CONFIG" nixos-rebuild "$mode" --flake "$BS_FLAKE#$BS_HOST" || return 1
  if [[ "$mode" == "boot" ]]; then
    bs_info "the new system starts at the next boot: reboot, then re-run this script to finish"
    BS_REBOOT=1
  fi
}

# step (--with-tailscale): log into the tailnet once tailscaled runs; Tailscale SSH comes from the config
step_tailscale() {
  (( BS_WITH_TAILSCALE )) || { bs_info "skipped (--with-tailscale to log in)"; return 0; }
  if (( ${BS_REBOOT:-0} )) || ! systemctl is-active --quiet tailscaled 2>/dev/null; then
    bs_info "tailscaled isn't running yet: reboot, then re-run with --with-tailscale"
    return 0
  fi
  if tailscale status >/dev/null 2>&1; then
    bs_info "already on the tailnet as $(tailscale status --self --json 2>/dev/null | sed -n 's/.*"DNSName": *"\([^".]*\).*/\1/p' | head -n 1)"
    return 0
  fi
  bs_run sudo tailscale up
}

bs_parse_args "$@"
bs_steps step_host step_checkout step_env step_hardware step_system step_tailscale
