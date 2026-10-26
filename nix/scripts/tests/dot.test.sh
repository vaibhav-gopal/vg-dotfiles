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
# (every XDG directory dot uses, not just HOME: a session's own XDG_STATE_HOME would put the read
# news in the real home)
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" XDG_STATE_HOME="$tmp/home/.local/state"
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
has "standard: the nix topic" "Nix: finding"
out="$(DOT_REPO="$tmp/repo" "$admin" help 2>&1)"
has "admin: the admin's topics" "adminonly"
hasnt "admin: not the standard users' topics" "standardonly"
has "admin: its built-in topics" "bootstrap"
has "admin: the nix topic" "Nix: finding"
out="$("$standard" help nix 2>&1)"
has "a built-in topic's article shows (nix)" "nix profile add"
out="$(DOT_REPO="$tmp/repo" "$admin" help everyone 2>&1)"
has "admin reads a topic's file live from the checkout" "LIVE copy"
out="$("$standard" help everyone 2>&1)"
has "a standard user reads the store copy" "STORE copy"
out="$("$standard" help mine 2>&1)"
has "a topic's inline text shows" "my tip"
out="$("$standard" help nosuch 2>&1)"; rc=$?
fails "an unknown topic fails"
has "and says so" "no help topic 'nosuch'"

echo "news"
# the machine's notes as Nix writes them (notes <id:date:profiles>...), and dot run in a terminal
# (script gives it one: the brief only shows to a terminal)
export DOT_SYSTEM_NEWS="$tmp/news.json"
notes() {
  local n id date profiles json='{}'
  for n in "$@"; do
    IFS=: read -r id date profiles <<<"$n"
    json="$(jq --arg id "$id" --arg d "$date" --arg p "$profiles" \
      '.[$id] = { date: $d, title: "note \($id)", text: "about \($id)", profiles: ($p | split(",")) }' <<<"$json")"
  done
  printf '%s\n' "$json" >"$DOT_SYSTEM_NEWS"
}
interm() { script -qec "$*" /dev/null 2>&1 | tr -d '\r'; }
notes n1:2026-01-01:admin,standard n2:2026-01-02:standard a1:2026-01-02:admin
out="$("$standard" help 2>&1)"
hasnt "not a terminal (a script, a pipe): no news" "note n1"
if [[ ! -e "$tmp/home/.local/state/dot/news-seen" ]]; then pass "and none of it is marked read"; else fail "and none of it is marked read"; fi
out="$("$standard" news --login)"
has "at login, a line pointing at the unread notes" "^2 new notes on .*: dot news$"
out="$(interm "$standard" help)"
has "one or two unread notes show in full before a command" "note n1"
has "with their text" "about n2"
hasnt "only the profile's notes" "note a1"
has "and the command still runs" "Help topics"
out="$(interm "$standard" help)"
hasnt "once read, they don't show again" "note n"
out="$("$standard" news --login)"
if [[ -z "$out" ]]; then pass "nor at login"; else fail "nor at login" "$out"; fi
out="$("$standard" news)"
if grep -q "note n2" <<<"$out" && ! grep -q "(new)" <<<"$out"; then pass "dot news shows them all, none new"; else fail "dot news shows them all, none new" "$out"; fi
if [[ "$(grep -n 'note n2' <<<"$out" | cut -d: -f1)" -lt "$(grep -n 'note n1' <<<"$out" | cut -d: -f1)" ]]; then pass "newest first"; else fail "newest first" "$out"; fi
notes n1:2026-01-01:admin,standard n2:2026-01-02:standard a1:2026-01-02:admin n3:2026-01-03:standard n4:2026-01-04:standard n5:2026-01-05:standard
out="$(interm "$standard" help)"
has "three or more unread: a count" "3 new notes on .*: dot news"
hasnt "not the notes themselves" "note n3"
out="$(interm "$standard" help)"
has "which stay unread until dot news" "3 new notes"
out="$("$standard" news)"
has "dot news marks the unread ones" "note n5  (new)"
out="$(interm "$standard" help)"
hasnt "and reads them" "new notes"
out="$(interm "$admin" help)"
has "the admin's dot shows the admin's notes" "note a1"

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
# the tenstorrent hook installs the machine's ttnn: run as shipped, with the machine's file moved
# into $tmp and a uv that records what it's asked to install (no ttnn yet; python finds none, so
# no SFPI download)
hook="$(sed -n 's/^DOT_SHARE="\(.*\)"$/\1/p' "$standard")/devshell/layers/tenstorrent/hook"
mkdir -p "$tmp/fakebin"
cat >"$tmp/fakebin/uv" <<EOF
#!/usr/bin/env bash
[[ "\$1 \$2" == "pip show" ]] && exit 1
echo "\$*" >>"$tmp/uv.log"
EOF
printf '#!/usr/bin/env bash\nexit 1\n' >"$tmp/fakebin/python"
chmod +x "$tmp/fakebin/uv" "$tmp/fakebin/python"
runhook() { rm -f "$tmp/uv.log"; PATH="$tmp/fakebin:$PATH" bash -c "$(sed "s|/etc/tenstorrent/ttnn-version|$tmp/ttnn-version|g" "$hook")" >/dev/null 2>&1; cat "$tmp/uv.log" 2>/dev/null; }
echo "0.81.1" >"$tmp/ttnn-version"
out="$(runhook)"
has "the tenstorrent shell installs the ttnn the machine names" "^pip install --quiet ttnn==0.81.1$"
rm -f "$tmp/ttnn-version"
out="$(runhook)"
has "and the newest where the machine names none" "^pip install --quiet ttnn$"
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
out="$(nix eval --raw "$src/nix#nixosConfigurations.vgsquid-jade.config.environment.etc.\"tenstorrent/ttnn-version\".text" 2>&1)"
has "jade names the ttnn its card's firmware takes, for the dev shells" "^0.81.1$"

(( failures == 0 )) || { echo "$failures check(s) failed"; exit 1; }
echo "all checks passed"
