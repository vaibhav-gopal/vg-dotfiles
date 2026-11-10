#!/usr/bin/env bash
# What a change must pass before it's committed: every host evaluates, the shared home layer builds
# (vgwsl2's home-files, ~1.1 GiB: a build failure that evaluation missed shipped once), the profiles and
# exports keep their shape, the scripts pass shellcheck and their tests, every flake template starts a
# project that passes its own checks, and (where the machine has KVM) the guests stay isolated on a shared
# host (a NixOS VM test). This repo runs no CI: these are the record, run on a Linux machine with Nix
# before every commit (vgwsl2: wsl -d NixOS -- bash nix/scripts/check.sh).
# tend: vg-dotfiles/Composition
#
# Usage: bash nix/scripts/check.sh        (from anywhere in the repo)
# Exit:  0 when every step that ran passes, 1 when any fails (every step runs either way); a step this
#        machine can't run (the VM test without /dev/kvm) is said to be skipped, never counted as passed.
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
step "profiles" bash nix/scripts/tests/profiles.test.sh
step "build the home layer (vgwsl2)" \
  "${NIX[@]}" build -L --no-link ./nix#homeConfigurations.vgwsl2.config.home-files
# nix/dot/*.sh are shellchecked as one script when dot builds (writeShellApplication)
step "shellcheck" "${NIX[@]}" develop --command \
  shellcheck -x nix/scripts/*.sh nix/scripts/bootstrap/*.sh nix/scripts/tests/*.sh
step "bootstrap tests" bash nix/scripts/tests/bootstrap.test.sh
step "wallpaper tests" bash nix/scripts/tests/wallpaper.test.sh
step "dot tests" bash nix/scripts/tests/dot.test.sh
step "flake templates" bash nix/scripts/tests/templates.test.sh
skipped=()
if [[ -e /dev/kvm ]]; then
  step "guest isolation (NixOS VM test)" "${NIX[@]}" build -L --no-link ./nix#checks.x86_64-linux.isolation
else
  skipped+=("guest isolation (NixOS VM test: no /dev/kvm here)")
fi

if ((${#skipped[@]})); then
  printf '\nskipped, not run: %s\n' "${skipped[*]}"
fi
if ((${#failed[@]})); then
  printf '\n%d step(s) failed: %s\n' "${#failed[@]}" "${failed[*]}"
  exit 1
fi
printf '\nevery check that ran passed\n'
