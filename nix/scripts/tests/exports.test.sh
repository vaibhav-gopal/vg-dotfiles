#!/usr/bin/env bash
# shellcheck disable=SC2016 # the single-quoted arguments are Nix expressions: their ${...} is Nix's
# The flake's exports (nix/flake.nix: `configurations`, `estate`, versioned by `exports.version`) keep
# the shape version 1 promises, so a change that renames or drops a field fails here until the version
# is bumped (and this test with it). Reads the real flake; builds nothing.
# Usage: bash nix/scripts/tests/exports.test.sh   (exit 1 on a failed check)
# tend: vg-dotfiles/Composition
set -uo pipefail

flake="${EXPORTS_FLAKE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}" # the nix/ directory (a real path: path: flakes refuse symlinks)
failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }

# A Nix check over the outputs: each names the first host and field that breaks it, or "ok"
check() { # check <description> <nix expression over `f` (the flake), giving "ok" or what's wrong>
  local got
  got="$(nix --extra-experimental-features "nix-command flakes" eval --raw --no-write-lock-file --impure --expr "
    let f = builtins.getFlake \"path:$flake\"; lib = f.inputs.nixpkgs.lib;
        firstBad = xs: let bad = builtins.filter (x: x != \"ok\") xs; in if bad == [ ] then \"ok\" else builtins.head bad;
    in $2" 2>&1 | tail -n 1)"
  if [[ "$got" == ok ]]; then pass "$1"; else fail "$1: $got"; fi
}

echo "exports"
check "exports.version is 1 and lists both outputs" \
  'if f.exports.version == 1 && f.exports.outputs == [ "configurations" "estate" ] then "ok" else "exports is ${builtins.toJSON f.exports}"'

check "every configurations host has the six v1 fields, as strings" '
  firstBad (lib.mapAttrsToList (h: c:
    let missing = builtins.filter (k: !(c ? ${k}) || !builtins.isString c.${k})
          [ "username" "system" "hostname" "version" "homedirectory" "nixType" ];
    in if missing == [ ] then "ok" else "${h} lacks ${toString missing}") f.configurations)'

check "every configurations host has a known nixType" '
  firstBad (lib.mapAttrsToList (h: c:
    if builtins.elem c.nixType [ "nixos" "nixos-wsl" "nix-darwin" ] then "ok" else "${h}: nixType ${c.nixType}") f.configurations)'

check "estate covers the same hosts as configurations" '
  if builtins.attrNames f.estate == builtins.attrNames f.configurations then "ok"
  else "estate ${toString (builtins.attrNames f.estate)} vs ${toString (builtins.attrNames f.configurations)}"'

check "every estate host has services, each with name and kind, and only v1 fields" '
  firstBad (lib.mapAttrsToList (h: e:
    let extra = builtins.filter (k: !builtins.elem k [ "services" "hosted_on" ]) (builtins.attrNames e);
        badSvc = builtins.filter (s:
          !(s ? name && s ? kind && builtins.isString s.name && builtins.isString s.kind)
          || builtins.any (k: !builtins.elem k [ "name" "kind" "unit" "tailnet_only" "notes" ]) (builtins.attrNames s)) e.services;
    in if extra != [ ] then "${h} has ${toString extra}"
       else if badSvc != [ ] then "${h}: service ${builtins.toJSON (builtins.head badSvc)}"
       else "ok") f.estate)'

check "hosted_on, where set, names a string" '
  firstBad (lib.mapAttrsToList (h: e: if !(e ? hosted_on) || builtins.isString e.hosted_on then "ok" else "${h}: hosted_on") f.estate)'

if (( failures )); then echo "$failures check(s) failed"; exit 1; fi
echo "all checks passed"
