#!/usr/bin/env bash
# Evaluate every machine in the flake (system + home-manager) without building anything.
# tend: vg-dotfiles/Composition
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

names() { # names <output> : the configurations an output defines; none is a failure (the flake didn't
  # evaluate: a loop over nothing passed vacuously once, from a worktree whose .git nix couldn't read)
  local list
  list="$("${NIX[@]}" eval --no-write-lock-file --json "$FLAKE#$1" --apply builtins.attrNames 2>"$errlog" \
    | tr -d '[]"' | tr ',' '\n' | sed '/^$/d')"
  if [[ -z "$list" ]]; then
    report FAIL "$1" "lists no configurations: $(grep 'error' "$errlog" | tail -n 1 | sed 's/^ *//')" >&2
    return 1
  fi
  printf '%s\n' "$list"
}

echo "nixosConfigurations"
hosts="$(names nixosConfigurations)" || failed=1
for host in $hosts; do
  needs=""
  [[ -d "$FLAKE/nixos/$host" ]] && needs="nixos/$host/hardware-configuration.nix" # bare metal (not wsl)
  check "$host" "nixosConfigurations.$host.config.system.build.toplevel.drvPath" "$needs"
done

echo "darwinConfigurations"
hosts="$(names darwinConfigurations)" || failed=1
for host in $hosts; do
  check "$host" "darwinConfigurations.$host.config.system.build.toplevel.drvPath"
done

echo "homeConfigurations"
hosts="$(names homeConfigurations)" || failed=1
for host in $hosts; do
  check "$host" "homeConfigurations.$host.activationPackage.drvPath"
done

exit "$failed"
