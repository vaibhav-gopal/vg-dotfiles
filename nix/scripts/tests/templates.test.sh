#!/usr/bin/env bash
# Tests for the flake templates (dev-utils/nix-templates, the root flake's `templates`): each one starts a
# project, in a throwaway git repo, whose own `nix flake check` passes, whose program prints its greeting
# and whose dev shell has its tools; and the check fails once the project's test is broken (the control).
# Usage: bash nix/scripts/tests/templates.test.sh [name...]   (default: every template ; exit 1 on a failed check)
# NOTE:  the templates are read from git: `git add` new template files before testing them.
# tend: vg-dotfiles/Dev utils
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)" # the repo root (its flake has `templates`)
NIX=(nix --extra-experimental-features "nix-command flakes")
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
expect() { local desc="$1"; shift; if "$@"; then pass "$desc"; else fail "$desc"; fi; }
quiet() { "$@" >"$tmp/last.log" 2>&1 || { sed 's/^/        /' "$tmp/last.log" | tail -n 25; return 1; }; }

# per template: a tool its dev shell must have, and the file holding its test's expected greeting
tool_of() { case "$1" in rust) echo "cargo --version" ;; cpp) echo "cmake --version" ;; bun) echo "bun --version" ;;
  python) echo "python -c 'import hello'" ;; *) echo "true" ;; esac; }
test_of() { case "$1" in rust) echo src/main.rs ;; cpp) echo tests/greet_test.cpp ;; bun) echo src/greet.test.ts ;;
  python) echo tests/test_greet.py ;; *) echo "" ;; esac; }

if (($#)); then names=("$@"); else
  read -r -a names <<<"$("${NIX[@]}" eval --raw "$root#templates" \
    --apply 'ts: builtins.concatStringsSep " " (builtins.filter (n: n != "default") (builtins.attrNames ts))')"
fi
# no template listed means the flake didn't evaluate: fail rather than pass over nothing
((${#names[@]})) || { echo "  FAIL  the flake lists no templates (it didn't evaluate)"; exit 1; }

for name in "${names[@]}"; do
  echo "template: $name"
  dir="$tmp/$name"
  mkdir -p "$dir" && cd "$dir" || exit 1
  git init -q

  expect "nix flake init copies it" quiet "${NIX[@]}" flake init -t "$root#$name"
  git add -A
  expect "its flake locks" quiet "${NIX[@]}" flake lock
  git add -A
  expect "its nix flake check passes" quiet "${NIX[@]}" flake check -L
  expect "its dev shell has its tools ($(tool_of "$name"))" quiet "${NIX[@]}" develop --command bash -c "$(tool_of "$name")"

  testfile="$(test_of "$name")"
  if [ -n "$testfile" ]; then
    out="$("${NIX[@]}" build --no-link --print-out-paths 2>"$tmp/last.log")"
    expect "its program prints Hello, world!" test "$("$out/bin/hello" 2>&1)" = "Hello, world!"

    # control: the same check with the test expecting another greeting must fail
    sed -i 's/Hello, nix!/Goodbye, nix!/g' "$testfile"
    git add -A
    if "${NIX[@]}" flake check -L >"$tmp/last.log" 2>&1; then rc=0; else rc=1; fi
    expect "its check fails once its test is broken ($testfile)" test "$rc" -eq 1
    expect "and the failure is that test's (its log shows the broken expectation)" grep -q 'Goodbye, nix!' "$tmp/last.log"
  fi
  cd "$tmp" || exit 1
done

if ((failures)); then echo "$failures check(s) failed"; exit 1; fi
echo "all checks passed"
