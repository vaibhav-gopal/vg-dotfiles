# shellcheck shell=bash
# What both `dot`s share: output, and the help topics (the machine's /etc/dot/help.json filtered by
# profile, the user's ~/.config/dot/help.json, and each dot's built-in topics). Prepended to admin.sh
# or standard.sh by nix/dot/package.nix, which sets DOT_PROFILE, DOT_SHARE and DOT_REPO_DEFAULT.
# tend: vg-dotfiles/Composition/dot

DOT_SYSTEM_HELP="${DOT_SYSTEM_HELP:-/etc/dot/help.json}"
DOT_USER_HELP="${DOT_USER_HELP:-${XDG_CONFIG_HOME:-$HOME/.config}/dot/help.json}"

if [[ -t 1 ]]; then
  B=$'\033[1m' DIM=$'\033[2m' BLUE=$'\033[34m' RED=$'\033[31m' YELLOW=$'\033[33m' N=$'\033[0m'
else
  B="" DIM="" BLUE="" RED="" YELLOW="" N=""
fi

say() { printf '%s\n' "$*"; }
head1() { printf '%s%s%s\n' "$B$BLUE" "$*" "$N"; }
warn() { printf '%swarn:%s %s\n' "$YELLOW" "$N" "$*" >&2; }
die() { printf '%serror:%s %s\n' "$RED" "$N" "$*" >&2; exit 1; }

# Markdown to the terminal: glow when it's a terminal, plain text otherwise
render_md() { # render_md <file>  (or stdin with -)
  if [[ -t 1 ]]; then glow -s auto -- "$1"; else cat -- "$1"; fi
}

# Every topic this user can see, as one JSON object: name -> {title, text, file, path}. Built-in
# topics come from dot_builtin_topics (each dot defines it), then the machine's, then the user's.
help_topics() {
  local sys='{}' usr='{}'
  [[ -r "$DOT_SYSTEM_HELP" ]] && sys="$(jq --arg p "$DOT_PROFILE" \
    'with_entries(select((.value.profiles // ["admin","standard"]) | index($p)))' "$DOT_SYSTEM_HELP")"
  [[ -r "$DOT_USER_HELP" ]] && usr="$(cat "$DOT_USER_HELP")"
  jq -n --argjson b "$(dot_builtin_topics)" --argjson s "$sys" --argjson u "$usr" '$b + $s + $u'
}

help_list() { # the topics, one line each
  help_topics | jq -r 'to_entries | sort_by(.key)[] | "\(.key)\t\(.value.title)"' \
    | while IFS=$'\t' read -r name title; do printf '  %s%-16s%s %s\n' "$B" "$name" "$N" "$title"; done
}

help_show() { # help_show <topic>
  local topics t text file path src
  topics="$(help_topics)"
  t="$(jq -c --arg n "$1" '.[$n] // empty' <<<"$topics")"
  [[ -n "$t" ]] || die "no help topic '$1' (dot help lists them)"
  head1 "$(jq -r .title <<<"$t")"
  text="$(jq -r '.text // ""' <<<"$t")"
  [[ -z "$text" ]] || { say; say "$text"; }
  file="$(jq -r '.file // empty' <<<"$t")"
  path="$(jq -r '.path // empty' <<<"$t")"
  [[ -n "$file$path" ]] || return 0
  # the admin reads the live file in the checkout (what they're editing), everyone else the store copy
  src="$path"
  if [[ "$DOT_PROFILE" == admin && -n "$file" ]]; then
    local live; live="$(dot_repo 2>/dev/null)/$file"
    [[ -r "$live" ]] && src="$live"
  fi
  [[ -r "$src" ]] || { warn "the long form ($file) isn't readable here"; return 0; }
  say
  render_md "$src"
}

# dot help [topic]: the commands and the topics, or one topic
cmd_help() {
  if [[ $# -gt 0 ]]; then help_show "$1"; return; fi
  dot_usage
  say
  head1 "Help topics (dot help <topic>)"
  help_list
}
