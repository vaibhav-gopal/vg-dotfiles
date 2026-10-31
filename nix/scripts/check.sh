#!/usr/bin/env bash
# What a change must pass before it's committed: every host evaluates, the shared home layer builds
# (vgwsl2's home-files, ~1.1 GiB: a build failure that evaluation missed shipped once), the exports
# keep their shape, and the scripts pass shellcheck and their tests. This repo runs no CI: these are
# the record, run on a Linux machine with Nix before every commit (vgwsl2: wsl -d NixOS -- bash nix/scripts/check.sh).
# tend: vg-dotfiles/Composition
#
# Usage: bash nix/scripts/check.sh        (from anywhere in the repo ; `just check` runs it too)
# Exit:  0 when every step passes, 1 when any fails (every step runs either way).
# NOTE:  flakes only see files git tracks: `git add` new files before checking them.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1
NIX=(nix --extra-experimental-features "nix-command flakes")
failed=()

step() { # step <name> <command...>
  local name="$1"
  shift
  printf '\n== %s\n' "$name"
  if "$@"; then
    printf '   ok: %s\n' "$name"
  else
    printf '   FAILED: %s\n' "$name"
    failed+=("$name")
  fi
}

step "evaluate every host" bash nix/scripts/check-hosts.sh
step "exports keep their shape" bash nix/scripts/tests/exports.test.sh
step "build the home layer (vgwsl2)" \
  "${NIX[@]}" build -L --no-link ./nix#homeConfigurations.vgwsl2.config.home-files
step "shellcheck" "${NIX[@]}" develop --command \
  shellcheck -x bootstrap.sh nix/scripts/*.sh nix/scripts/bootstrap/*.sh nix/scripts/tests/*.sh
step "bootstrap tests" bash nix/scripts/tests/bootstrap.test.sh
step "wallpaper tests" bash nix/scripts/tests/wallpaper.test.sh

if ((${#failed[@]})); then
  printf '\n%d step(s) failed: %s\n' "${#failed[@]}" "${failed[*]}"
  exit 1
fi
printf '\nevery check passed\n'
