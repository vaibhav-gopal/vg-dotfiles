# Guest isolation on a box shared with other people (the standard users in profiles.users): the host is the owner's
# own tailnet node, so a guest must not reach past it, nor see the owner's or each other's work.
# - network: guests (primary group `guests`, which their Slurm jobs run under too) reach the internet
#   and MagicDNS only, never the tailnet or the LAN; inbound, the tailnet gets sshd alone
#   (modules.tailscale.trustTailnet off). The same holds for the Nix daemon's build users (nixbld):
#   a fixed-output derivation downloads as one, so a guest's build would otherwise reach the LAN for
#   them. The pool is shared, so the admin's builds can't fetch from there either (substitution runs
#   as root and flake inputs as the user, so neither is affected). A guest's rootless containers are
#   theirs too: their subordinate uids (a container's own users) get the rule
# - processes: /proc is mounted hidepid=invisible, so a guest sees only their own; the owner and the
#   services that inspect other users' processes are in `proc`
# - /tmp, /var/tmp, /dev/shm: each guest's sessions get private ones (pam_namespace), and each Slurm
#   job its own (modules.slurm)
# tend: vg-dotfiles/NixOS/Core
{ config, lib, usrlib, pkgs, username, ... }:
let
  cfg = config.core.headless.isolation;
  guests = config.profiles.standard;
  procGid = config.ids.gids.proc;

  # MagicDNS (the host's only resolver) stays reachable inside the blocked ranges
  dns4 = "100.100.100.100";
  dns6 = "fd7a:115c:a1e0::53";
  # the tailnet (CGNAT range, Tailscale's ULA), the LAN (RFC 1918, ULA) and link-local
  blocked4 = [ "100.64.0.0/10" "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "169.254.0.0/16" ];
  blocked6 = [ "fd7a:115c:a1e0::/48" "fc00::/7" "fe80::/10" ];
  # the guests' own processes and jobs, and every build's downloads
  groups = [ "guests" "nixbld" ];
  # A rootless container's own users are the guest's subordinate uids (/etc/subuid, assigned at
  # activation, so read when the firewall starts): with --network host their sockets are theirs, not
  # the guest's, and would pass the group match
  subRanges = ''
    for u in ${lib.escapeShellArgs guests}; do
      ${pkgs.gawk}/bin/awk -F: -v u="$u" '$1 == u { print $2 "-" $2 + $3 - 1 }' /etc/subuid 2>/dev/null
    done
  '';
  unhook = ipt: lib.concatMapStrings (g: ''
    ${ipt} -D OUTPUT -m owner --gid-owner ${g} --suppl-groups -j guest-egress 2>/dev/null || true
  '') groups + ''
    for r in $(${subRanges}); do ${ipt} -D OUTPUT -m owner --uid-owner "$r" -j guest-egress 2>/dev/null || true; done
  '';
  egressRules = ipt: dns: blocked: ''
    ${ipt} -N guest-egress 2>/dev/null || ${ipt} -F guest-egress
    ${ipt} -A guest-egress -d ${dns} -p udp --dport 53 -j RETURN
    ${ipt} -A guest-egress -d ${dns} -p tcp --dport 53 -j RETURN
    ${lib.concatMapStrings (net: "${ipt} -A guest-egress -d ${net} -j REJECT\n") blocked}
    ${unhook ipt}
    ${lib.concatMapStrings (g: "${ipt} -I OUTPUT 1 -m owner --gid-owner ${g} --suppl-groups -j guest-egress\n") groups}
    for r in $(${subRanges}); do ${ipt} -I OUTPUT 1 -m owner --uid-owner "$r" -j guest-egress; done
  '';
  egressStop = ipt: ''
    ${unhook ipt}
    ${ipt} -F guest-egress 2>/dev/null || true
    ${ipt} -X guest-egress 2>/dev/null || true
  '';

  # nixpkgs' pam_namespace reads its config from linux-pam's store path; this copy reads /etc/security
  pamNamespace = pkgs.linux-pam.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace modules/pam_namespace/pam_namespace.h \
        --replace-fail '(SCONFIG_DIR "/namespace' '("/etc/security/namespace'
    '';
  });
  # instance dirs live under a root-only prefix; `~` limits polyinstantiation to the listed users
  instances = "/var/lib/guest-tmp";
  users = "~${lib.concatStringsSep "," guests}";
  namespaceRule = {
    control = "required";
    modulePath = "${pamNamespace}/lib/security/pam_namespace.so";
    # after pam_unix and pam_loginuid, before pam_systemd
    order = config.security.pam.services.sshd.rules.session.systemd.order - 10;
  };
in {
  options.core.headless.isolation = {
    enable = usrlib.mkEnableOptionFalse "isolate the guest accounts: no tailnet or LAN from them, hidden processes, private /tmp";
  };

  config = lib.mkIf (cfg.enable && guests != [ ]) {
    users.groups.guests = { };
    users.users = lib.genAttrs guests (_: { group = "guests"; })
      // { ${username}.extraGroups = [ "proc" ]; };

    networking.firewall.extraCommands = egressRules "iptables" dns4 blocked4 + egressRules "ip6tables" dns6 blocked6;
    networking.firewall.extraStopCommands = egressStop "iptables" + egressStop "ip6tables";
    modules.tailscale.trustTailnet = false;

    # hidepid, as nixpkgs' old security.hideProcessInformation did, plus polkit (it checks the
    # processes asking it for authorization)
    boot.specialFileSystems."/proc".options = [ "hidepid=2" "gid=${toString procGid}" ];
    users.groups.proc.gid = procGid;
    systemd.services.systemd-logind.serviceConfig.SupplementaryGroups = [ "proc" ];
    systemd.services.polkit.serviceConfig.SupplementaryGroups = [ "proc" ];

    dot.help.privacy = {
      title = "What's private on this shared machine, and what you can reach from it";
      profiles = [ "standard" ];
      text = ''
        Your home directory, your /tmp, /var/tmp and /dev/shm are yours alone (a job gets its own /tmp too).
        You see only your own processes (ps, top) and your own Slurm jobs.
        From here you reach the internet, not the machine owner's network or tailnet.
        Something blocked that your work needs? Ask the admin.
      '';
    };

    environment.etc."security/namespace.conf".text = ''
      /tmp     ${instances}/tmp-     user   ${users}
      /var/tmp ${instances}/vartmp-  user   ${users}
      /dev/shm /dev/shm              tmpfs  ${users}
    '';
    systemd.tmpfiles.rules = [ "d ${instances} 0000 root root -" ];
    # the ssh sessions, and the user manager (systemd-run --user) they start
    security.pam.services.sshd.rules.session.namespace = namespaceRule;
    security.pam.services.systemd-user.rules.session.namespace = namespaceRule;
  };
}
