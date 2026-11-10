#!/usr/bin/env bash
# Tests for profiles (nix/modules/profiles.nix, home/modules/profile.nix): evaluates vgsquid-jade, the
# host with standard users, and checks what each profile gets, who shares which folder, that a host
# mask and a user's own settings override a feature's default, that the assertions refuse a second
# admin and keys or folders for an unknown user, and that help topics come and go with their module.
# Nothing is built.
# Usage: bash nix/scripts/tests/profiles.test.sh   (exit 1 if any check fails)
# tend: vg-dotfiles/Shared
set -uo pipefail

flake="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG
}experimental-features = nix-command flakes"
failures=0
errlog="$(mktemp)"
trap 'rm -f "$errlog"' EXIT

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; [[ -z "${2:-}" ]] || printf '        %s\n' "$2"; failures=$((failures + 1)); }

# facts <extra module, as a nix expression>: one JSON object of what the checks read
facts() {
  nix eval --json "$flake#nixosConfigurations.vgsquid-jade" --apply "sys: let
    c = (sys.extendModules { modules = [ ($1) ]; }).config;
    h = u: c.home-manager.users.\${u};
    f = u: let x = h u; in {
      profile = x.profile.name;
      folders = x.common.folders.enable;
      autostart = x.common.term.zellij.auto_start;
      kitty = x.common.term.kitty.enable;
      zed = x.common.editor.zed.enable;
      claude = x.common.claude-code.enable;
      claudeProfiles = x.common.claude-code.profiles;
      gh = x.common.git.gh.enable;
      rustup = x.common.rustup.enable;
      gitName = x.common.git.name;
      liveNvim = !(builtins.isPath x.xdg.configFile.nvim.source);
      home = x.home.homeDirectory;
      user = x.home.username;
    };
  in {
    admin = f \"vaibhav\";
    standard = f \"yaxpatel\";
    standardGroup = c.users.users.yaxpatel.group;
    sshUsers = c.services.openssh.settings.AllowUsers;
    egress = c.networking.firewall.extraCommands;
    linger = c.users.users.yaxpatel.linger;
    podman = c.virtualisation.podman.enable;
    help = builtins.attrNames c.dot.help;
    news = builtins.fromJSON c.environment.etc.\"dot/news.json\".text;
    newsAtLogin = sys.pkgs.lib.hasInfix \"dot news --login\" c.environment.interactiveShellInit;
    sleep = c.systemd.sleep.settings.Sleep;
    gnomeLocks = builtins.concatMap (d: d.locks or [ ]) c.programs.dconf.profiles.user.databases;
    xFlags = c.services.xserver.serverFlagsSection;
    kernelParams = c.boot.kernelParams;
    sharedGroups = builtins.mapAttrs (_: g: g.members)
      (sys.pkgs.lib.filterAttrs (n: _: sys.pkgs.lib.hasPrefix \"shared-\" n) c.users.groups);
    sharedRules = builtins.filter (sys.pkgs.lib.hasInfix \"/srv/shared\") c.systemd.tmpfiles.rules;
    failed = map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
  }" 2>"$errlog" || tail -3 "$errlog"
}
# check <description> <json> <jq filter that must be true>
check() {
  if jq -e "$3" >/dev/null 2>&1 <<<"$2"; then pass "$1"; else fail "$1" "$(jq -c "$3" <<<"$2" 2>&1 | head -c 300)"; fi
}

echo "vgsquid-jade as configured"
base="$(facts '{ }')"
jq -e . >/dev/null 2>&1 <<<"$base" || { fail "evaluates" "$(tail -3 <<<"$base")"; exit 1; }
check "admin is vaibhav, in his own home" "$base" '.admin.profile == "admin" and .admin.user == "vaibhav" and .admin.home == "/home/vaibhav"'
check "admin keeps the personal features" "$base" '.admin.folders and .admin.autostart and .admin.gitName == "Vaibhav Gopal" and .admin.claudeProfiles == ["personal","work"]'
check "admin's configs link live into the checkout" "$base" '.admin.liveNvim'
check "standard user is yaxpatel, in their own home" "$base" '.standard.profile == "standard" and .standard.user == "yaxpatel" and .standard.home == "/home/yaxpatel"'
check "standard user gets the toolchains, plain claude and gh" "$base" '.standard.claude and .standard.claudeProfiles == [] and .standard.gh and .standard.rustup'
check "standard user gets none of the opinionated or personal features" "$base" '(.standard.folders or .standard.autostart or .standard.kitty or .standard.zed) | not'
check "standard user has no managed git identity" "$base" '.standard.gitName == null'
check "standard user's configs are store copies" "$base" '.standard.liveNvim | not'
check "standard users are isolated (group guests)" "$base" '.standardGroup == "guests"'
check "sshd admits exactly the users with ssh logins" "$base" '.sshUsers == ["sameerjuin","siddhpatel","vaibhav","yaxpatel"]'
check "the egress rule covers the guests and the build users (a build downloads as nixbld)" "$base" '(.egress | test("gid-owner guests")) and (.egress | test("gid-owner nixbld"))'
check "the egress rule covers the guests' container users (their subordinate uids)" "$base" '.egress | test("/etc/subuid") and test("uid-owner")'
check "jade's colleagues linger, and have containers" "$base" '.linger and .podman'
check "Slurm's help topics are there (its module is on)" "$base" '.help | index("slurm") != null and index("slurm-admin") != null'
check "every user shares the everyone folder (the default)" "$base" '.sharedGroups["shared-everyone"] | sort == ["sameerjuin","siddhpatel","vaibhav","yaxpatel"]'
check "jade's capstone folder: the three colleagues and the admin" "$base" '.sharedGroups["shared-capstone"] | sort == ["sameerjuin","siddhpatel","vaibhav","yaxpatel"]'
check "a shared folder is members-only and setgid, with the group's default ACL" "$base" '(.sharedRules | index("d /srv/shared/capstone 2770 root shared-capstone -") != null) and (.sharedRules | any(test("^a\\+ /srv/shared/capstone .*default:group::rwx,default:mask::rwx,default:other::---")))'
check "the shared help topic is there" "$base" '.help | index("shared") != null'
check "jade's news reaches /etc/dot/news.json, dated, for its standard users" "$base" '(.news | keys == ["2026-10-25-help","2026-10-25-shared-folders","2026-10-25-ttnn-pin"]) and all(.news[]; .date == "2026-10-25" and .profiles == ["standard"])'
check "and a login points at what's unread" "$base" '.newsAtLogin'
check "jade never sleeps (every kind refused at systemd)" "$base" '.sleep == {"AllowHibernation":"no","AllowHybridSleep":"no","AllowSuspend":"no","AllowSuspendThenHibernate":"no"}'
check "nor idles at the console: GNOME's sleep, dim, blank, screensaver and lock off and locked" "$base" '["/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type","/org/gnome/settings-daemon/plugins/power/idle-dim","/org/gnome/desktop/session/idle-delay","/org/gnome/desktop/screensaver/idle-activation-enabled","/org/gnome/desktop/screensaver/lock-enabled"] - .gnomeLocks == []'
check "nor at the login screen (X never blanks) or the text console" "$base" '(.xFlags | test("\"BlankTime\" \"0\"") and test("\"OffTime\" \"0\"")) and (.kernelParams | index("consoleblank=0") != null)'
check "no assertion fails" "$base" '.failed == []'

echo "overrides"
masked="$(facts '{ profiles.masks."term.zellij.auto_start" = [ "admin" "standard" ]; }')"
check "a host mask turns a feature on for standard users" "$masked" '.standard.autostart and .admin.autostart'
own="$(facts '{ profiles.users.yaxpatel.home.common.folders.enable = true; }')"
check "a user's own settings turn one on just for them" "$own" '.standard.folders'
noEveryone="$(facts '{ profiles.shared.everyone = [ ]; }')"
check "a host can drop the everyone folder, and keeps its own" "$noEveryone" '(.sharedGroups | has("shared-everyone") | not) and (.sharedGroups | has("shared-capstone"))'

echo "refused"
twoAdmins="$(facts '{ profiles.users.yaxpatel.profile = "admin"; }')"
check "a second admin" "$twoAdmins" '.failed | any(test("the only admin"))'
strayKeys="$(facts '{ core.headless.sshd.userKeys.nobody = [ "ssh-ed25519 AAAA" ]; }')"
check "keys for a user who isn't in profiles.users" "$strayKeys" '.failed | any(test("userKeys.nobody"))'
strayMember="$(facts '{ profiles.shared.capstone = [ "nobody" ]; }')"
check "a shared folder member who isn't in profiles.users" "$strayMember" '.failed | any(test("profiles.shared.capstone: nobody "))'

echo "help comes and goes with its module"
noSlurm="$(facts '{ lib, ... }: { modules.slurm.enable = lib.mkForce false; }')"
check "no Slurm, no Slurm topics" "$noSlurm" '.help | index("slurm") == null'
check "someone lingers, so the background topic is there" "$base" '.help | index("background") != null'
noLinger="$(facts '{ lib, ... }: { profiles.users = lib.genAttrs [ "yaxpatel" "sameerjuin" "siddhpatel" ] (_: { linger = lib.mkForce false; }); }')"
check "nobody lingers, no background topic" "$noLinger" '.help | index("background") == null'

(( failures == 0 )) || { echo "$failures check(s) failed"; exit 1; }
echo "all checks passed"
