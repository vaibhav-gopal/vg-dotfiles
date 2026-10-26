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

# dot devshell [--print] [layer...]: one flake.nix from the layers in $DOT_SHARE/devshell/layers
# (see its README): those named, what they require, and base, in that order
devshell_resolve() { # the layers in order, each once: requirements before what needs them
  local l r
  for l in "$@"; do
    [[ -d "$DOT_SHARE/devshell/layers/$l" ]] || die "no layer '$l' (dot devshell lists them)"
    if [[ -r "$DOT_SHARE/devshell/layers/$l/requires" ]]; then
      while read -r r; do [[ -n "$r" ]] && devshell_resolve "$r"; done <"$DOT_SHARE/devshell/layers/$l/requires"
    fi
    printf '%s\n' "$l"
  done
}
devshell_section() { # devshell_section <file> <indent> <layer...>: that file of each layer, under its name
  local file="$1" pad="$2" l; shift 2
  for l in "$@"; do
    local f="$DOT_SHARE/devshell/layers/$l/$file"
    [[ -s "$f" ]] || continue
    printf '%s# %s\n' "$pad" "$l"
    sed "s/^/$pad/" "$f"
  done
}
devshell_render() { # devshell_render <layer...>: the flake.nix
  local layers=("$@") libs
  libs="$(devshell_section libs "" "${layers[@]}" | { grep -v '^#' || true; } | sort -u | paste -sd' ')" # none is fine
  cat <<NIX
# Dev shell made by \`dot devshell ${layers[*]}\`; it's yours to edit and keep in git.
# Packages: nixpkgs attribute names (dot find <word>). Enter with \`nix develop\`, or \`direnv allow\`.
{
  description = "dev shell: ${layers[*]}";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; config.allowUnfree = true; }));
    in {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
$(devshell_section packages "            " "${layers[@]}")
          ];
NIX
  if [[ -n "$libs" ]]; then
    cat <<NIX
          # libraries prebuilt binaries and wheels (manylinux) expect from the system
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (with pkgs; [ $libs ]);
NIX
  fi
  devshell_section env "          " "${layers[@]}"
  cat <<NIX
          shellHook = ''
$(devshell_section hook "            " "${layers[@]}")
          '';
        };
      });
    };
}
NIX
}
cmd_devshell() {
  local print=0 l
  [[ "${1:-}" == --print ]] && { print=1; shift; }
  if [[ $# -eq 0 ]]; then
    head1 "Layers (dot devshell <layer>..., e.g. dot devshell python tenstorrent)"
    for l in "$DOT_SHARE"/devshell/layers/*; do printf '  %s%-12s%s %s\n' "$B" "$(basename "$l")" "$N" "$(cat "$l/about")"; done
    say; say "${DIM}--print writes the flake to stdout instead (to merge into an existing one).$N"
    return
  fi
  local layers=()
  mapfile -t layers < <(devshell_resolve base "$@" | awk '!seen[$0]++')
  if ((print)); then devshell_render "${layers[@]}"; return; fi
  [[ ! -e flake.nix ]] || die "this folder already has a flake.nix (dot devshell --print ${*} shows what it would write)"
  devshell_render "${layers[@]}" >flake.nix
  [[ -e .envrc ]] || echo "use flake" >.envrc
  if [[ ! -e .gitignore ]] || ! grep -qx '.direnv/' .gitignore; then printf '.direnv/\n.venv/\n' >>.gitignore; fi
  say "Wrote flake.nix (layers: ${layers[*]}), .envrc and .gitignore. Next:"
  say "  git add flake.nix .envrc .gitignore   # a flake only sees files git knows about"
  say "  nix develop                           # or direnv allow, to enter it whenever you cd here"
}
