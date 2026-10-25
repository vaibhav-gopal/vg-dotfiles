# shellcheck shell=bash
# The admin's `dot`: apply, inspect and maintain this machine from the vg-dotfiles checkout, and
# bring up a new one (`dot bootstrap`). The machine is $DOT_HOST, .env's NIXCONFIG, else the hostname; its
# archetype comes from the flake's configurations table. Help and output come from lib.sh.
# tend: vg-dotfiles/Composition/dot

# A fresh install has no flakes enabled: on for dot and everything it starts
export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG
}experimental-features = nix-command flakes
warn-dirty = false"

dot_usage() {
  cat <<EOF
${B}dot${N} - this machine, from the vg-dotfiles checkout (admin)

${B}Apply${N}
  dot apply [--boot]            build and switch (--boot: from the next boot, for kernel changes)
  dot diff                      build, and show what would change against the running system
  dot update                    bump flake.lock (then dot diff / dot apply)
  dot gc [--all]                delete generations older than 7 days (--all: every old one)
${B}Check${N}
  dot check [--all]             evaluate this machine (--all: every machine and home)
  dot test                      the repo's test suite (nix/scripts/tests)
  dot status                    machine, generation, checkout
${B}Inspect${N}  (--home: the home layer, of --user <name> or yours)
  dot users                     who logs in here: profile, logins, keys
  dot features                  every masked home feature, on or off for each user
  dot options [--home] [path]   options with type, value and default (default: this repo's)
  dot config [--home] <path>    a configuration value, as JSON
  dot pkgs [--home]             installed packages
  dot session [--user <name>]   shell aliases and session variables
${B}Users${N}
  dot user reset <name>         a one-time password for a standard user (changed at first login)
  dot passwd                    change your password (at the machine, not over ssh)
${B}Setup${N}
  dot bootstrap [host] [opts]   bring this machine up to its configuration (clones the repo first)
  dot brew <bootstrap|adopt|check|file>   Homebrew on nix-darwin
  dot cd | dot edit             print the checkout's path (cd "\$(dot cd)") | open it in \$EDITOR
  dot help [topic]              this, or a help topic
EOF
}

dot_builtin_topics() { cat "$DOT_SHARE/topics.json"; }

# The checkout: $DOT_REPO, the home layer's, the git repo we're in, or ~/vg-dotfiles
dot_repo() {
  local r
  for r in "${DOT_REPO:-}" "$DOT_REPO_DEFAULT" "$(git rev-parse --show-toplevel 2>/dev/null)" "$HOME/vg-dotfiles"; do
    [[ -n "$r" && -f "$r/nix/flake.nix" ]] && { printf '%s\n' "$r"; return; }
  done
  return 1
}
repo() { dot_repo || die "no vg-dotfiles checkout (~/vg-dotfiles); dot bootstrap clones it"; }

env_get() { # env_get <key>: from the checkout's .env
  local f; f="$(repo)/.env"
  if [[ -r "$f" ]]; then sed -n "s/^$1=//p" "$f" | head -n 1; fi
}
host() { local h="${DOT_HOST:-}"; [[ -n "$h" ]] || h="$(env_get NIXCONFIG)"; printf '%s\n' "${h:-$(uname -n)}"; }
nixtype() {
  local t=""; [[ -n "${DOT_HOST:-}" ]] || t="$(env_get NIXTYPE)" # .env describes its own host
  [[ -n "$t" ]] || t="$(nix eval --raw "$(repo)/nix#configurations.$(host).nixType" 2>/dev/null)" \
    || die "$(host) is not a machine in nix/flake.nix"
  printf '%s\n' "$t"
}
sysattr() { # the flake attribute of this machine's system
  if [[ "$(nixtype)" == nix-darwin ]]; then echo "darwinConfigurations.$(host)"; else echo "nixosConfigurations.$(host)"; fi
}
rebuild() { if [[ "$(nixtype)" == nix-darwin ]]; then echo darwin-rebuild; else echo nixos-rebuild; fi; }
deval() { # deval <function> [apply expr]: nix#dot.<host>.<function>, as JSON
  nix eval --json "$(repo)/nix#dot.$(host).$1" ${2:+--apply "$2"}
}
qs() { local s=$1; s=${s//\\/\\\\}; printf '"%s"' "${s//\"/\\\"}"; } # a nix string literal

# Parse --home / --user <name> into HOME_MODE / FOR_USER; the rest stays in ARGS
parse_target() {
  HOME_MODE=0 FOR_USER="$(id -un)" ARGS=()
  while (($#)); do
    case "$1" in
      --home) HOME_MODE=1 ;;
      --user) HOME_MODE=1; FOR_USER="${2:?--user needs a name}"; shift ;;
      *) ARGS+=("$1") ;;
    esac
    shift
  done
}

table_options() { # rows JSON on stdin -> path  type  = value  (default)  description
  jq -r '.[] | [.path, .type, .value, .default, (.description | split("\n") | .[0] // "")] | map(gsub("\n"; " ")) | join("\u001f")' | while IFS=$'\x1f' read -r p t v d desc; do
    printf '%s%s%s  %s%s%s\n    = %s' "$B" "$p" "$N" "$DIM" "$t" "$N" "$v"
    [[ -z "$d" || "$d" == "$v" ]] || printf '  %s(default: %s)%s' "$DIM" "$d" "$N"
    printf '\n'
    [[ -z "$desc" ]] || printf '    %s%s%s\n' "$DIM" "${desc%%$'\n'*}" "$N"
  done
}

cmd_apply() {
  local mode=switch
  case "${1:-}" in --boot) mode=boot ;; "") ;; *) die "dot apply [--boot]" ;; esac
  head1 "$(rebuild) $mode: $(host)"
  sudo -H "$(rebuild)" "$mode" --flake "$(repo)/nix#$(host)"
}

cmd_diff() {
  local out
  head1 "Building $(host)"
  out="$(nix build --no-link --print-out-paths "$(repo)/nix#$(sysattr).config.system.build.toplevel")" || die "the build failed"
  if [[ "$out" == "$(readlink -f /run/current-system)" ]]; then say "Nothing to apply: the running system is this build."; return; fi
  head1 "What changes against the running system"
  nix store diff-closures /run/current-system "$out"
  say; say "dot apply switches to it."
}

cmd_update() {
  head1 "Updating flake.lock"
  nix flake update --flake "$(repo)/nix"
  git -C "$(repo)" diff --stat -- nix/flake.lock
}

cmd_gc() {
  case "${1:-}" in
    --all) sudo -H nix-collect-garbage -d ;;
    "") sudo -H nix-collect-garbage --delete-older-than 7d ;;
    *) die "dot gc [--all]" ;;
  esac
  du -sh /nix/store 2>/dev/null
}

cmd_check() {
  if [[ "${1:-}" == --all ]]; then bash "$(repo)/nix/scripts/check-hosts.sh"; return; fi
  head1 "Evaluating $(host)"
  nix eval --raw "$(repo)/nix#$(sysattr).config.system.build.toplevel.drvPath" && echo
}

cmd_test() {
  local t rc=0
  for t in "$(repo)"/nix/scripts/tests/*.test.sh; do
    head1 "$(basename "$t")"
    bash "$t" || rc=1
  done
  return "$rc"
}

cmd_status() {
  local r; r="$(repo)"
  head1 "$(host) ($(nixtype))"
  say "  running   $(readlink -f /run/current-system 2>/dev/null)"
  [[ -e /nix/var/nix/profiles/system ]] && say "  profile   $(readlink /nix/var/nix/profiles/system)  (switched $(stat -c %y /nix/var/nix/profiles/system | cut -c1-16))"
  head1 "Checkout $r"
  git -C "$r" status -sb | head -n 15
}

cmd_users() {
  deval users | jq -r 'to_entries[] | [.key, .value.profile, (.value.logins | join(",")), (.value.keys | tostring)] | @tsv' \
    | { printf '%s%-14s %-9s %-14s %s%s\n' "$B" USER PROFILE LOGINS KEYS "$N"; while IFS=$'\t' read -r u p l k; do printf '%-14s %-9s %-14s %s\n' "$u" "$p" "$l" "$k"; done; }
}

cmd_features() {
  local json users
  json="$(deval features)"
  users="$(deval users | jq -r 'keys | join(" ")')"
  printf '%s%-26s' "$B" FEATURE; for u in $users; do printf ' %-11s' "${u:0:11}"; done; printf '%s\n' "$N"
  jq -r --arg users "$users" '.[] | [.mask] + [ .on[($users | split(" "))[]] ] | @tsv' <<<"$json" \
    | while IFS=$'\t' read -r -a row; do
        printf '%-26s' "${row[0]}"
        for v in "${row[@]:1}"; do if [[ "$v" == true ]]; then printf ' %s%-11s%s' "$B" on "$N"; else printf ' %s%-11s%s' "$DIM" off "$N"; fi; done
        printf '\n'
      done
  say; say "${DIM}A host changes a mask with profiles.masks.<feature>; one user with profiles.users.<name>.home.$N"
}

cmd_options() {
  parse_target "$@"; local path="${ARGS[0]:-}"
  if ((HOME_MODE)); then deval homeOptions "f: f $(qs "$path") $(qs "$FOR_USER")" | table_options
  else deval sysOptions "f: f $(qs "$path")" | table_options; fi
}

cmd_config() {
  parse_target "$@"; local path="${ARGS[0]:-}"
  [[ -n "$path" ]] || die "dot config [--home] <path>, e.g. dot config services.openssh.settings"
  if ((HOME_MODE)); then nix eval --json "$(repo)/nix#$(sysattr).config.home-manager.users.$FOR_USER.$path" | jq
  else nix eval --json "$(repo)/nix#$(sysattr).config.$path" | jq; fi
}

cmd_pkgs() {
  parse_target "$@"
  if ((HOME_MODE)); then deval homePkgs "f: f $(qs "$FOR_USER")"; else deval sysPkgs; fi | jq -r '.[]' | sort -u | column -c "${COLUMNS:-100}"
}

cmd_session() {
  parse_target "$@"
  deval session "f: f $(qs "$FOR_USER")" | jq -r '
    "\u001b[1mAliases\u001b[0m", (.aliases | to_entries[] | "  \(.key) = \(.value)"),
    "\u001b[1mSession variables\u001b[0m", (.variables | to_entries[] | "  \(.key) = \(.value)")'
}

cmd_user() {
  [[ "${1:-}" == reset && -n "${2:-}" ]] || die "dot user reset <name>"
  local name="$2" profile
  profile="$(deval users | jq -r --arg u "$name" '.[$u].profile // empty')"
  [[ "$profile" == standard ]] || die "$name is not a standard user here (dot users)"
  say "A one-time password for $name: they change it at their first login."
  sudo passwd "$name" && sudo passwd --expire "$name"
}

cmd_passwd() {
  [[ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ]] || die "the admin's password changes at the machine, not over ssh"
  passwd
}

cmd_bootstrap() {
  local r archetype
  r="$(dot_repo || true)"
  if [[ -z "$r" ]]; then
    r="$HOME/vg-dotfiles"
    head1 "Cloning vg-dotfiles to $r"
    git clone https://github.com/vaibhav-gopal/vg-dotfiles.git "$r"
  fi
  if [[ "$(uname -s)" == Darwin ]]; then archetype=nix-darwin
  elif [[ -n "${WSL_DISTRO_NAME:-}" || -e /proc/sys/fs/binfmt_misc/WSLInterop ]]; then archetype=nixos-wsl
  elif [[ -e /etc/NIXOS ]]; then archetype=nixos
  else die "not NixOS, NixOS-WSL or macOS; nothing here bootstraps this system"; fi
  exec bash "$r/nix/scripts/bootstrap/$archetype.sh" "$@"
}

cmd_brew() {
  [[ "$(nixtype)" == nix-darwin ]] || die "Homebrew is for nix-darwin machines"
  local cfg; cfg="$(repo)/nix#darwinConfigurations.$(host).config"
  # shellcheck source=/dev/null
  source "$(repo)/nix/scripts/homebrew.sh"
  case "${1:-}" in
    bootstrap) brew_bootstrap "$cfg" ;;
    adopt) brew_adopt "$cfg" ;;
    check) brew_check "$cfg" ;;
    file) brew_brewfile "$cfg" ;;
    *) die "dot brew <bootstrap|adopt|check|file>" ;;
  esac
}

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    apply | diff | update | gc | check | test | status | users | features | options | config | pkgs | session | user | passwd | bootstrap | brew)
      "cmd_$cmd" "$@" ;;
    cd) repo ;;
    edit) exec "${EDITOR:-vi}" "$(repo)" ;;
    help | -h | --help) cmd_help "$@" ;;
    *) die "no command '$cmd' (dot help)" ;;
  esac
}
