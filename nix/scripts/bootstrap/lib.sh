#!/usr/bin/env bash
# shellcheck disable=SC2034 # the BS_* options are read by the archetype scripts that source this
# Bootstrap steps shared by every archetype: logging, the step runner, host lookup and .env.
# Sourced by nixos.sh, nixos-wsl.sh and nix-darwin.sh; every step is idempotent (it checks before it
# changes anything), so a bootstrap can be re-run at any point and only does what is left.
# tend: vg-dotfiles/Composition/Bootstrap

# The repo root, from this file's place in it (nix/scripts/bootstrap/lib.sh)
BS_ROOT="${BS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
BS_FLAKE="$BS_ROOT/nix"

# A fresh install has no flakes enabled: turn them on for this process and everything it starts
export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG
}experimental-features = nix-command flakes"

# Options every archetype script accepts (bs_parse_args fills them; the scripts that source this read them)
BS_HOST=""
BS_DRY_RUN=0
BS_MODE="auto" # auto | switch | boot
BS_WITH_HOMEBREW=0
BS_WITH_TAILSCALE=0
BS_REGEN_HARDWARE=0

bs_info() { printf '  %s\n' "$*"; }
bs_warn() { printf '  \033[33mwarn:\033[0m %s\n' "$*" >&2; }
bs_die() { printf '  \033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Run a command, or only print it under --dry-run
bs_run() {
  if (( BS_DRY_RUN )); then
    printf '  would run: %s\n' "$*"
  else
    "$@"
  fi
}

bs_usage() {
  cat <<EOF
Usage: $(basename "$0") [host] [options]

Brings this machine up to its configuration in the flake, from a fresh clone. Safe to re-run:
every step checks first and skips what is already done.

  host                 a machine in nix/flake.nix (default: .env's NIXCONFIG, then \`hostname\`)
  --dry-run            check and evaluate only; change nothing
  --switch | --boot    how to apply the system (default: boot when the kernel changes, else switch)
  --with-homebrew      nix-darwin: install Homebrew and adopt hand-installed casks first
  --with-tailscale     nixos: log this machine into the tailnet (\`tailscale up\`) once tailscaled runs
  --regen-hardware     nixos: replace the repo's hardware-configuration.nix with this machine's
  -h, --help           this help
EOF
}

bs_parse_args() {
  while (( $# )); do
    case "$1" in
      --dry-run) BS_DRY_RUN=1 ;;
      --switch) BS_MODE="switch" ;;
      --boot) BS_MODE="boot" ;;
      --with-homebrew) BS_WITH_HOMEBREW=1 ;;
      --with-tailscale) BS_WITH_TAILSCALE=1 ;;
      --regen-hardware) BS_REGEN_HARDWARE=1 ;;
      -h|--help) bs_usage; exit 0 ;;
      -*) bs_usage >&2; bs_die "unknown option: $1" ;;
      *) [[ -z "$BS_HOST" ]] || bs_die "one host only (got $BS_HOST and $1)"; BS_HOST="$1" ;;
    esac
    shift
  done
}

# Run the named step functions in order, numbered; any failure stops the bootstrap.
# A step runs on the left of `||`, where `set -e` doesn't reach: steps return their failures.
bs_steps() {
  local i=0 n=$# step
  for step in "$@"; do
    i=$((i + 1))
    printf '\033[1m[%d/%d] %s\033[0m\n' "$i" "$n" "${step#step_}"
    "$step" || bs_die "step ${step#step_} failed"
  done
  printf '\033[1mdone\033[0m\n'
}

# A value from the KEY=value file $1 (empty if absent)
bs_env_get() {
  [[ -f "$1" ]] || return 0
  sed -n "s/^$2=//p" "$1" | tail -n 1
}

# The host's entry in the flake's configurations table, as JSON (overridden in tests)
bs_host_json() {
  nix eval --json --no-write-lock-file "$BS_FLAKE#configurations.$1" 2>/dev/null
}

# A field of that JSON entry (no jq on a fresh install)
bs_json_field() {
  sed -n "s/.*\"$2\":\"\\([^\"]*\\)\".*/\\1/p" <<<"$1"
}

# Which machine this is: the argument, else .env's NIXCONFIG, else the hostname
bs_resolve_host() {
  [[ -n "$BS_HOST" ]] || BS_HOST="$(bs_env_get "$BS_ROOT/.env" NIXCONFIG)"
  [[ -n "$BS_HOST" ]] || BS_HOST="$(hostname -s 2>/dev/null || hostname)"
}

# step: the host exists in the flake for this archetype; sets BS_NIXTYPE and BS_USERNAME
step_host() {
  bs_resolve_host
  local json
  json="$(bs_host_json "$BS_HOST")" || true
  [[ -n "$json" ]] || bs_die "no machine '$BS_HOST' in nix/flake.nix (pass the host name, or add it to configurations first: README, Adding a machine)"
  BS_NIXTYPE="$(bs_json_field "$json" nixType)"
  BS_USERNAME="$(bs_json_field "$json" username)"
  [[ "$BS_NIXTYPE" == "$BS_ARCHETYPE" ]] || bs_die "$BS_HOST is a $BS_NIXTYPE machine, not $BS_ARCHETYPE: run nix/scripts/bootstrap/$BS_NIXTYPE.sh"
  bs_info "$BS_HOST ($BS_NIXTYPE, user $BS_USERNAME)"
}

# step: the clone is where the live-edited config links point, and the right user runs this
step_checkout() {
  local want="$HOME/vg-dotfiles"
  if [[ "$BS_ROOT" != "$want" && "$(cd "$want" 2>/dev/null && pwd -P)" != "$(cd "$BS_ROOT" && pwd -P)" ]]; then
    bs_warn "the clone is at $BS_ROOT; config links point at ~/vg-dotfiles (extPaths.dotfilesDir), so move it there or set that option"
  else
    bs_info "clone at $want"
  fi
  if [[ "$(id -un)" != "$BS_USERNAME" ]]; then
    bs_warn "running as $(id -un), but the configuration's user is $BS_USERNAME"
  fi
}

# The .env `dot` reads, for this host
bs_env_text() {
  local version
  version="$(bs_env_get "$BS_ROOT/.template-env" NIXCONFIG_VERSION)"
  printf 'NIXTYPE=%s\nNIXCONFIG=%s\nNIXCONFIG_VERSION=%s\nNIXCONFIG_USERNAME=%s\n' \
    "$BS_NIXTYPE" "$BS_HOST" "$version" "$BS_USERNAME"
}

# step: .env selects this host (an older one is kept as .env.bak)
step_env() {
  local env="$BS_ROOT/.env" want line
  want="$(bs_env_text)"
  if [[ -f "$env" && "$(cat "$env")" == "$want" ]]; then
    bs_info ".env already selects $BS_HOST"
    return 0
  fi
  if (( BS_DRY_RUN )); then
    bs_info "would write .env:"
    while IFS= read -r line; do bs_info "  $line"; done <<<"$want"
    return 0
  fi
  [[ -f "$env" ]] && cp "$env" "$env.bak" && bs_info "previous .env kept as .env.bak"
  printf '%s\n' "$want" >"$env"
  bs_info "wrote .env for $BS_HOST"
}

# Build the host's system without applying it; prints the store path (dry-run: evaluates only)
bs_build_system() { # bs_build_system <flake attribute of the system toplevel>
  if (( BS_DRY_RUN )); then
    nix eval --raw --no-write-lock-file "$BS_FLAKE#$1.drvPath" >/dev/null || return 1
    return 0
  fi
  nix build --no-link --print-out-paths --no-write-lock-file "$BS_FLAKE#$1"
}
