#!/usr/bin/env bash
# Bootstrap a Mac with nix installed from a fresh clone: host, checkout, .env, optionally Homebrew
# (install it and adopt hand-installed casks, before the first build applies the Brewfile), and the
# first darwin-rebuild (nix-darwin itself comes from its flake the first time). Idempotent.
# Usage: nix/scripts/bootstrap/nix-darwin.sh [host] [--dry-run] [--with-homebrew]
# tend: vg-dotfiles/Composition/Bootstrap
set -euo pipefail
# shellcheck source=nix/scripts/bootstrap/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=nix/scripts/homebrew.sh
source "$BS_ROOT/nix/scripts/homebrew.sh"
BS_ARCHETYPE="nix-darwin"

# step (--with-homebrew): Homebrew installed, and casks installed by hand adopted, before the build
step_homebrew() {
  local config="$BS_FLAKE#darwinConfigurations.$BS_HOST.config"
  if (( ! BS_WITH_HOMEBREW )); then
    if ! brew_bin >/dev/null && [[ -n "$(brew_cask_tokens "$config" 2>/dev/null)" ]]; then
      bs_warn "casks are declared but Homebrew isn't installed: re-run with --with-homebrew"
    else
      bs_info "skipped (--with-homebrew to install Homebrew and adopt casks)"
    fi
    return 0
  fi
  if (( BS_DRY_RUN )); then
    if brew_bin >/dev/null; then bs_info "Homebrew at $(brew_bin)"; else bs_info "would install Homebrew"; fi
    bs_info "would adopt hand-installed casks"
    return 0
  fi
  brew_install || return 1
  brew_adopt "$config" || bs_warn "some casks weren't adopted (listed above); the build installs or skips them"
}

# step: build the system and switch to it; the first time, darwin-rebuild comes from nix-darwin's flake
step_system() {
  local out version
  out="$(bs_build_system "darwinConfigurations.$BS_HOST.config.system.build.toplevel")" || return 1
  if (( BS_DRY_RUN )); then
    bs_info "the system evaluates; would build and switch to it"
    return 0
  fi
  if [[ "$(readlink -f /run/current-system 2>/dev/null)" == "$out" ]]; then
    bs_info "already running this system"
    return 0
  fi
  if command -v darwin-rebuild >/dev/null; then
    sudo -H env NIX_CONFIG="$NIX_CONFIG" darwin-rebuild switch --flake "$BS_FLAKE#$BS_HOST" || return 1
  else
    version="$(bs_env_get "$BS_ROOT/.template-env" NIXCONFIG_VERSION)"
    sudo -H env NIX_CONFIG="$NIX_CONFIG" nix run "nix-darwin/nix-darwin-$version#darwin-rebuild" -- switch --flake "$BS_FLAKE#$BS_HOST" || return 1
  fi
}

command -v nix >/dev/null || bs_die "nix isn't installed: install it first (https://nixos.org/download), then re-run"
bs_parse_args "$@"
bs_steps step_host step_checkout step_env step_homebrew step_system
