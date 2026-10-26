# shellcheck shell=bash
# The standard users' `dot`: working on a machine you don't administer. What's installed for you,
# getting more without root (nix shell, dev shells from a template), your account, and the help
# topics of the features on this machine. Help and output come from lib.sh.
# tend: vg-dotfiles/Composition/dot

dot_usage() {
  cat <<EOF
${B}dot${N} - your tools and help on $(uname -n)

  dot tools [word]              what's installed for you (filter by a word)
  dot find <word>               search every package nix has
  dot shell <pkg>...            a shell with those packages, gone when you exit
  dot run <pkg> [args]          run a package once
  dot devshell [layer...]       a dev shell for the project in this folder (python, tenstorrent, ...)
  dot whoami                    your account here
  dot passwd                    set or change your password
  dot help [topic]              this, or a help topic
  dot news                      what's changed on this machine

You can't use sudo or install system-wide; everything above stays in your account.
EOF
}

dot_builtin_topics() { cat "$DOT_SHARE/topics.json"; }

cmd_tools() {
  local f="${XDG_CONFIG_HOME:-$HOME/.config}/dot/tools.json"
  [[ -r "$f" ]] || die "no tools list ($f)"
  jq -r --arg w "${1:-}" '.[] | select(($w == "") or (.name + " " + .description | ascii_downcase | contains($w | ascii_downcase))) | [.name, .description] | join("\u001f")' "$f" \
    | sort -u | while IFS=$'\x1f' read -r n d; do printf '  %s%-18s%s %s\n' "$B" "$n" "$N" "$d"; done
  say; say "${DIM}Not here? dot find <word>, then dot shell <pkg>.$N"
}

cmd_find() {
  [[ $# -gt 0 ]] || die "dot find <word>"
  nix search nixpkgs "$@"
}

cmd_shell() {
  [[ $# -gt 0 ]] || die "dot shell <pkg>... (e.g. dot shell python3 uv)"
  local args=() p
  for p in "$@"; do args+=("nixpkgs#$p"); done
  say "${DIM}nix shell ${args[*]}  (exit to leave)$N"
  exec nix shell "${args[@]}"
}

cmd_run() {
  [[ $# -gt 0 ]] || die "dot run <pkg> [args]"
  local p="$1"; shift
  exec nix run "nixpkgs#$p" -- "$@"
}

cmd_whoami() {
  head1 "$(id -un) on $(uname -n)"
  say "  profile   standard (no sudo)"
  say "  groups    $(id -nG)"
  say "  home      $HOME ($(du -sh "$HOME" 2>/dev/null | cut -f1))"
  if command -v sacctmgr >/dev/null; then
    say "  slurm     $(sacctmgr -n -P show assoc user="$(id -un)" format=account 2>/dev/null | head -n 1)"
  fi
}

cmd_passwd() {
  if passwd -S "$(id -un)" 2>/dev/null | grep -qE '^\S+ (L|NP) '; then
    # the sudo rule names its store path
    sudo -n "$(readlink -f "$(command -v vg-first-password)")"
  else
    passwd
  fi
}

main() {
  local cmd="${1:-help}"; shift || true
  [[ "$cmd" == news ]] || news_brief
  case "$cmd" in
    tools | find | shell | run | devshell | whoami | passwd | news) "cmd_$cmd" "$@" ;;
    help | -h | --help) cmd_help "$@" ;;
    *) die "no command '$cmd' (dot help)" ;;
  esac
}
