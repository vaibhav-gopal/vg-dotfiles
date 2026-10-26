#!/usr/bin/env bash
# Tests for `dot` (nix/dot): builds both from the root flake and runs them in a throwaway home with
# stand-in help files, checking each profile sees its own topics, the admin reads a topic's file
# live from the checkout and a standard user the store copy, dev shells come from templates and
# never overwrite, and the refusals (an unknown command or topic, the admin's password over ssh,
# no checkout). Then the admin's inspection commands on the real vgsquid-jade configuration.
# Usage: bash nix/scripts/tests/dot.test.sh   (exit 1 if any check fails)
# tend: vg-dotfiles/Composition/dot
set -uo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG
}experimental-features = nix-command flakes
warn-dirty = false"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { # fail <description> [output to show]
  local line
  printf '  FAIL  %s\n' "$1"
  [[ -z "${2:-}" ]] || while IFS= read -r line; do printf '        %s\n' "$line"; done < <(head -n 8 <<<"$2")
  failures=$((failures + 1))
}
has() { if grep -q -- "$2" <<<"$out"; then pass "$1"; else fail "$1" "$out"; fi; }
hasnt() { if grep -q -- "$2" <<<"$out"; then fail "$1" "$out"; else pass "$1"; fi; }
fails() { if (( rc != 0 )); then pass "$1"; else fail "$1 (exit 0)" "$out"; fi; }

admin="$(nix build --no-link --print-out-paths "$src#dot")/bin/dot" || exit 1
standard="$(nix build --no-link --print-out-paths "$src#dot-standard")/bin/dot" || exit 1

# A throwaway home, a checkout with one doc in it, and the machine's help as Nix would write it
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config"
mkdir -p "$XDG_CONFIG_HOME/dot" "$tmp/repo/nix" "$tmp/store"
touch "$tmp/repo/nix/flake.nix"
echo "LIVE copy of the guide" >"$tmp/repo/guide.md"
echo "STORE copy of the guide" >"$tmp/store/guide.md"
cat >"$tmp/system.json" <<EOF
{
  "everyone": { "title": "for everyone", "text": "", "file": "guide.md", "path": "$tmp/store/guide.md", "profiles": ["admin", "standard"] },
  "adminonly": { "title": "for the admin", "text": "admin tip", "file": null, "path": null, "profiles": ["admin"] },
  "standardonly": { "title": "for standard users", "text": "standard tip", "file": null, "path": null, "profiles": ["standard"] }
}
EOF
echo '{ "mine": { "title": "a feature of mine", "text": "my tip", "file": null, "path": null } }' >"$XDG_CONFIG_HOME/dot/help.json"
echo '[ { "name": "ripgrep", "description": "Utility that combines the usability of The Silver Searcher" } ]' >"$XDG_CONFIG_HOME/dot/tools.json"
export DOT_SYSTEM_HELP="$tmp/system.json"
cd "$tmp/home" || exit 1

echo "help, by profile"
out="$("$standard" help 2>&1)"
has "standard: the machine's topics for everyone" "everyone"
has "standard: the topics for standard users" "standardonly"
hasnt "standard: not the admin's topics" "adminonly"
has "standard: the user's own feature topics" "mine"
has "standard: its built-in topics" "devshells"
out="$(DOT_REPO="$tmp/repo" "$admin" help 2>&1)"
has "admin: the admin's topics" "adminonly"
hasnt "admin: not the standard users' topics" "standardonly"
has "admin: its built-in topics" "bootstrap"
out="$(DOT_REPO="$tmp/repo" "$admin" help everyone 2>&1)"
has "admin reads a topic's file live from the checkout" "LIVE copy"
out="$("$standard" help everyone 2>&1)"
has "a standard user reads the store copy" "STORE copy"
out="$("$standard" help mine 2>&1)"
has "a topic's inline text shows" "my tip"
out="$("$standard" help nosuch 2>&1)"; rc=$?
fails "an unknown topic fails"
has "and says so" "no help topic 'nosuch'"

echo "tools and dev shells"
out="$("$standard" tools silver 2>&1)"
has "dot tools filters by a word in the description" "ripgrep"
out="$("$standard" tools nothing-matches-this 2>&1)"
hasnt "and leaves out what doesn't match" "ripgrep"
mkdir -p "$tmp/proj" && cd "$tmp/proj" || exit 1
out="$("$standard" devshell 2>&1)"
has "dot devshell lists the layers" "tenstorrent"
out="$("$standard" devshell --print python tenstorrent 2>&1)"
if [[ ! -e flake.nix ]]; then pass "--print writes no file"; else fail "--print writes no file"; fi
order="$(grep -oE '^ +# (base|python|tenstorrent)$' <<<"$out" | awk '{print $2}' | awk '!seen[$0]++' | paste -sd' ')"
if [[ "$order" == "base python tenstorrent" ]]; then pass "layers in order: base, then requirements, each once"; else fail "layers in order: base, then requirements, each once" "$order"; fi
if [[ "$(grep -c '^ *python312$' <<<"$out")" -eq 1 ]]; then pass "a layer named twice (python, and through tenstorrent) lands once"; else fail "a layer named twice lands once" "$out"; fi
has "the libraries wheels need are on LD_LIBRARY_PATH" "makeLibraryPath (with pkgs; \\[.*stdenv.cc.cc.lib.*\\])"
has "and the ones the prebuilt SFPI compiler needs (tenstorrent)" "makeLibraryPath (with pkgs; \\[.*libmpc.*mpfr.*\\])"
out="$("$standard" devshell tenstorrent 2>&1)"
has "tenstorrent alone pulls in python" "layers: base python tenstorrent"
if [[ -f flake.nix && -f .envrc && -f .gitignore ]]; then pass "it writes flake.nix, .envrc and .gitignore"; else fail "it writes flake.nix, .envrc and .gitignore" "$out"; fi
echo "# mine" >flake.nix
out="$("$standard" devshell base 2>&1)"; rc=$?
fails "a second dot devshell fails"
if [[ "$(cat flake.nix)" == "# mine" ]]; then pass "and leaves the existing flake.nix alone"; else fail "and leaves the existing flake.nix alone"; fi
out="$("$standard" devshell nosuch 2>&1)"; rc=$?
fails "an unknown layer fails"
mkdir -p "$tmp/cpp" && cd "$tmp/cpp" || exit 1
out="$("$standard" devshell cpp 2>&1)"
if [[ -f flake.nix ]] && ! grep -q LD_LIBRARY_PATH flake.nix; then pass "a shell with no libraries (cpp) is written, without LD_LIBRARY_PATH"; else fail "a shell with no libraries (cpp) is written" "$out"; fi
# every layer at once must still be a flake that evaluates (against the nixpkgs this repo pins)
mkdir -p "$tmp/all" && cd "$tmp/all" || exit 1
"$standard" devshell base python tenstorrent cpp rust node >/dev/null 2>&1
rev="$(jq -r .nodes.nixpkgs.locked.rev "$src/nix/flake.lock")"
out="$(nix eval --raw "path:$tmp/all#devShells.x86_64-linux.default.drvPath" --override-input nixpkgs "github:nixos/nixpkgs/$rev" 2>&1)"
has "every layer composed together evaluates" "nix-shell.drv"
cd "$tmp/home" || exit 1

echo "refusals"
out="$("$standard" nosuch 2>&1)"; rc=$?
fails "an unknown command fails (standard)"
out="$("$admin" nosuch 2>&1)"; rc=$?
fails "an unknown command fails (admin)"
out="$(SSH_CONNECTION="1.2.3.4 1 5.6.7.8 22" "$admin" passwd 2>&1)"; rc=$?
fails "the admin's password doesn't change over ssh"
has "and says where it does" "at the machine"
out="$("$admin" cd 2>&1)"; rc=$?
fails "no checkout: dot cd fails"
has "and points at dot bootstrap" "dot bootstrap clones it"
out="$(DOT_REPO="$tmp/repo" "$admin" cd 2>&1)"
has "DOT_REPO picks the checkout" "$tmp/repo"

echo "inspecting vgsquid-jade"
out="$(DOT_REPO="$src" DOT_HOST=vgsquid-jade "$admin" users 2>&1)"
has "dot users lists the admin" "vaibhav  *admin  *console,ssh"
has "and the standard users" "yaxpatel  *standard  *ssh"
out="$(DOT_REPO="$src" DOT_HOST=vgsquid-jade "$admin" features 2>&1)"
if grep -E '^folders' <<<"$out" | grep -q 'on' && [[ "$(grep -E '^folders' <<<"$out" | grep -o 'on' | wc -l)" -eq 1 ]]; then
  pass "dot features: folders on for the admin alone"
else
  fail "dot features: folders on for the admin alone" "$out"
fi
out="$(DOT_REPO="$src" DOT_HOST=vgsquid-jade "$admin" options modules.slurm 2>&1)"
has "dot options shows a value beside its default" "modules.slurm.enable"

(( failures == 0 )) || { echo "$failures check(s) failed"; exit 1; }
echo "all checks passed"
