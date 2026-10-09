#!/usr/bin/env bash
# Evaluate every machine in the flake (system + home-manager) without building anything.
# tend: dotfiles/Composition
#
# Forces each host's config.system.build.toplevel.drvPath and each homeConfigurations
# activationPackage.drvPath, so a broken module, option or assertion fails here instead of
# at `nixos-rebuild` time. Darwin hosts evaluate fine from Linux (nothing is built).
#
# A NixOS host whose hardware-configuration.nix isn't in git yet is reported as PENDING, not
# failed: that file is generated on the machine itself (nixos-generate-config).
#
# Usage: bash nix/scripts/check-hosts.sh        (from the repo root ; on Windows: wsl -d NixOS -- bash nix/scripts/check-hosts.sh)
# Exit:  0 when every host evaluates or is pending, 1 when any fails.
# NOTE:  flakes only see files git tracks: `git add` new files before checking them.

set -uo pipefail

FLAKE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" # the nix/ directory
NIX=(nix --extra-experimental-features "nix-command flakes")
failed=0

errlog="$(mktemp)"
trap 'rm -f "$errlog"' EXIT

eval_attr() { # stdout: the value only ; stderr (evaluation warnings, errors) goes to $errlog
  "${NIX[@]}" eval --no-write-lock-file --raw "$FLAKE#$1" 2>"$errlog"
}

report() { # report <status> <name> <detail>
  printf '  %-8s %-34s %s\n' "$1" "$2" "$3"
}

check() { # check <name> <attribute path> [pending-if-missing file]
  local name="$1" attr="$2" needs="${3:-}"
  if [[ -n "$needs" ]] && ! git -C "$FLAKE" ls-files --error-unmatch "$needs" >/dev/null 2>&1; then
    report PENDING "$name" "no $needs in git yet"
    return
  fi
  local out
  out="$(eval_attr "$attr")"
  if [[ "$out" == /nix/store/*.drv ]]; then
    report ok "$name" "$(basename "$out")"
  else
    report FAIL "$name" "$(grep 'error: .' "$errlog" | tail -n 1 | sed 's/^ *//')"
    failed=1
  fi
}

names() { # names <output> : the configurations an output defines
  "${NIX[@]}" eval --no-write-lock-file --json "$FLAKE#$1" --apply builtins.attrNames 2>/dev/null \
    | tr -d '[]"' | tr ',' '\n' | sed '/^$/d'
}

echo "nixosConfigurations"
for host in $(names nixosConfigurations); do
  needs=""
  [[ -d "$FLAKE/nixos/$host" ]] && needs="nixos/$host/hardware-configuration.nix" # bare metal (not wsl)
  check "$host" "nixosConfigurations.$host.config.system.build.toplevel.drvPath" "$needs"
done

echo "darwinConfigurations"
for host in $(names darwinConfigurations); do
  check "$host" "darwinConfigurations.$host.config.system.build.toplevel.drvPath"
done

echo "homeConfigurations"
for host in $(names homeConfigurations); do
  check "$host" "homeConfigurations.$host.activationPackage.drvPath"
done

exit "$failed"
