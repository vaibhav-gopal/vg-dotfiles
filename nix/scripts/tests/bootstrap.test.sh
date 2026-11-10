#!/usr/bin/env bash
# Tests for nix/scripts/bootstrap: runs the real nixos.sh in a throwaway repo with stand-in `nix`
# and `sudo` on PATH, so nothing is evaluated, built or applied. Checks every step is idempotent.
# Usage: bash nix/scripts/tests/bootstrap.test.sh   (exit 1 on the first failed check)
# tend: vg-dotfiles/Composition/Bootstrap
set -uo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { # fail <description> [output to show]
  local line
  printf '  FAIL  %s\n' "$1"
  [[ -z "${2:-}" ]] || while IFS= read -r line; do printf '        %s\n' "$line"; done <<<"$2"
  failures=$((failures + 1))
}
expect() { # expect <description> <command...>: the command succeeds
  local desc="$1"; shift
  if "$@"; then pass "$desc"; else fail "$desc" "$out"; fi
}

# A throwaway repo: the bootstrap scripts, .template-env and one host folder
repo="$tmp/repo"
mkdir -p "$repo/nix/scripts/bootstrap" "$repo/nix/nixos/testhost" "$tmp/bin" "$tmp/etc"
cp "$src"/nix/scripts/bootstrap/*.sh "$repo/nix/scripts/bootstrap/"
cp "$src/nix/scripts/homebrew.sh" "$repo/nix/scripts/"
printf 'NIXTYPE=nix-darwin\nNIXCONFIG=vgmacbook\nNIXCONFIG_VERSION=26.05\nNIXCONFIG_USERNAME=vaibhav\n' >"$repo/.template-env"
echo '{ ... }: { imports = [ ./hardware-configuration.nix ]; }' >"$repo/nix/nixos/testhost/default.nix"
echo '{ ... }: { fileSystems."/".device = "/dev/sda1"; }' >"$tmp/etc/hardware-configuration.nix"
git -C "$repo" init -q && git -C "$repo" add -A && git -C "$repo" -c user.name=t -c user.email=t@t commit -qm init

# Stand-ins: nix knows two hosts (FAKE_NIXTYPE sets their archetype); sudo only logs what it would run
cat >"$tmp/bin/nix" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"#configurations.testhost"*|*"#configurations.otherhost"*)
    h="${*##*#configurations.}"; h="${h%% *}"
    printf '{"homedirectory":"/home/tester","hostname":"%s","nixType":"%s","system":"x86_64-linux","username":"tester","version":"26.05"}\n' "$h" "${FAKE_NIXTYPE:-nixos}" ;;
  *"#configurations."*) exit 1 ;;
  eval*) echo /nix/store/fake-system.drv ;;
  build*) echo /nix/store/fake-system ;;
  *) exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\necho "$*" >>"%s/sudo.log"\n' "$tmp" >"$tmp/bin/sudo"
chmod +x "$tmp/bin/nix" "$tmp/bin/sudo"
# vg-repos stand-in: records how it was run (the real one would clone into the user's home)
printf '#!/usr/bin/env bash\necho "$*" >>"%s/repos.log"\n' "$tmp" >"$tmp/bin/vg-repos"
chmod +x "$tmp/bin/vg-repos"
export BS_REPOS="$tmp/bin/vg-repos"

run() { # run <args...>: nixos.sh in the throwaway repo; output in $out, status in $rc
  out="$(cd "$repo" && PATH="$tmp/bin:$PATH" BS_ETC_NIXOS="$tmp/etc" bash nix/scripts/bootstrap/nixos.sh "$@" 2>&1)"
  rc=$?
}
hw="$repo/nix/nixos/testhost/hardware-configuration.nix"

echo "bootstrap: nixos"

run testhost --dry-run
expect "dry run succeeds" test "$rc" -eq 0
expect "dry run writes no .env" test ! -e "$repo/.env"
expect "dry run copies no hardware config" test ! -e "$hw"
expect "dry run applies nothing" test ! -e "$tmp/sudo.log"
expect "dry run clones no repos" test ! -e "$tmp/repos.log"

run testhost --switch
expect "first run succeeds" test "$rc" -eq 0
expect ".env selects the host" grep -qx 'NIXCONFIG=testhost' "$repo/.env"
expect ".env has its archetype, user and release" \
  bash -c "grep -qx NIXTYPE=nixos '$repo/.env' && grep -qx NIXCONFIG_USERNAME=tester '$repo/.env' && grep -qx NIXCONFIG_VERSION=26.05 '$repo/.env'"
expect "hardware config copied from the machine" cmp -s "$hw" "$tmp/etc/hardware-configuration.nix"
expect "hardware config staged in git" git -C "$repo" ls-files --error-unmatch -- "$hw" >/dev/null
expect "system applied with nixos-rebuild switch" grep -q "nixos-rebuild switch --flake $repo/nix#testhost" "$tmp/sudo.log"
expect "tailscale skipped without --with-tailscale" grep -q 'skipped (--with-tailscale' <<<"$out"
expect "the repos are cloned interactively at the end" grep -qx -- --interactive "$tmp/repos.log"

run
expect "second run (host from .env) succeeds" test "$rc" -eq 0
expect "second run leaves .env alone" grep -q '.env already selects testhost' <<<"$out"
expect "second run keeps the hardware config" grep -q 'hardware-configuration.nix in place' <<<"$out"
expect "no .env.bak when nothing changed" test ! -e "$repo/.env.bak"

echo '{ ... }: { fileSystems."/".device = "/dev/nvme0n1p2"; }' >"$tmp/etc/hardware-configuration.nix"
run testhost --dry-run
expect "a differing hardware config is reported" grep -q 'keeping the repo' <<<"$out"
expect "and kept" grep -q sda1 "$hw"
run testhost --dry-run --regen-hardware
expect "--regen-hardware with --dry-run changes nothing" grep -q sda1 "$hw"
run testhost --switch --regen-hardware
expect "--regen-hardware replaces it and keeps a .bak" bash -c "grep -q nvme0n1p2 '$hw' && grep -q sda1 '$hw.bak'"

run otherhost --dry-run
expect "another host rewrites .env only in a real run" grep -qx 'NIXCONFIG=testhost' "$repo/.env"

run nosuchhost
expect "an unknown host fails" test "$rc" -ne 0
expect "an unknown host says so" grep -q "no machine 'nosuchhost'" <<<"$out"

FAKE_NIXTYPE=nix-darwin run testhost
expect "a host of another archetype fails" test "$rc" -ne 0
expect "and names the right script" grep -q 'run nix/scripts/bootstrap/nix-darwin.sh' <<<"$out"

run testhost --bogus
expect "an unknown option fails" test "$rc" -ne 0

if (( failures )); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
