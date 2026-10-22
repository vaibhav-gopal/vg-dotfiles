#!/usr/bin/env bash
# Tests for vg-wallpaper (home/modules/wallpapers): builds the script from vgkraken's home config and
# checks the image choice in throwaway folders (VG_WALLPAPER_DIR, XDG_STATE_HOME); no desktop is touched.
# Usage: bash nix/scripts/tests/wallpaper.test.sh   (exit 1 on a failed check)
# tend: vg-dotfiles/Home/wallpapers
set -uo pipefail

flake="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" # the nix/ directory
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
expect() { local desc="$1"; shift; if "$@"; then pass "$desc"; else fail "$desc"; fi; }

pkg="$(nix --extra-experimental-features "nix-command flakes" build --no-link --print-out-paths --no-write-lock-file \
  "$flake#homeConfigurations.vgkraken.config.common.wallpapers.package")" || { echo "build failed"; exit 1; }
wp() { XDG_STATE_HOME="$tmp/state" VG_WALLPAPER_DIR="$tmp/$1" "$pkg/bin/vg-wallpaper" "${@:2}"; }

echo "vg-wallpaper"
mkdir -p "$tmp/three" "$tmp/one" "$tmp/none"
touch "$tmp/three/a.jpg" "$tmp/three/b.png" "$tmp/three/c.webp" "$tmp/three/.hidden" "$tmp/one/only.jpg"

ok=1; for _ in $(seq 30); do case "$(wp three pick)" in "$tmp"/three/[abc].*) ;; *) ok=0 ;; esac; done
expect "picks only images in the folder, never dotfiles" test "$ok" -eq 1

mkdir -p "$tmp/state/vg-wallpaper"; echo "$tmp/three/a.jpg" >"$tmp/state/vg-wallpaper/last"
ok=1; for _ in $(seq 30); do [ "$(wp three pick)" != "$tmp/three/a.jpg" ] || ok=0; done
expect "never picks the image showing" test "$ok" -eq 1

seen="$(for _ in $(seq 60); do wp three pick; done | sort -u | wc -l)"
expect "shuffles across the others (saw $seen of 2)" test "$seen" -eq 2

echo "$tmp/one/only.jpg" >"$tmp/state/vg-wallpaper/last"
expect "with one image, picks it again" test "$(wp one pick)" = "$tmp/one/only.jpg"

expect "an empty folder picks nothing" test -z "$(wp none pick)"
wp none next gnome 2>/dev/null; rc=$?
expect "next fails on an empty folder (says the clone is missing)" test "$rc" -ne 0
wp three next nosuchdesktop 2>/dev/null; rc=$?
expect "an unknown desktop fails" test "$rc" -ne 0
expect "and records nothing" test "$(cat "$tmp/state/vg-wallpaper/last")" = "$tmp/one/only.jpg"

if (( failures )); then echo "$failures check(s) failed"; exit 1; fi
echo "all checks passed"
