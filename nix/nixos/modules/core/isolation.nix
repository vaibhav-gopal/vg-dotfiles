# Guest isolation on a box shared with other people (the standard users in profiles.users): the host is the owner's
# own tailnet node, so a guest must not reach past it, nor see the owner's or each other's work.
# - network: guests (primary group `guests`, which their Slurm jobs run under too) reach the internet
#   and MagicDNS only, never the tailnet or the LAN; inbound, the tailnet gets sshd alone
#   (modules.tailscale.trustTailnet off)
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
  match = "-m owner --gid-owner guests --suppl-groups";
  egressRules = ipt: dns: blocked: ''
    ${ipt} -N guest-egress 2>/dev/null || ${ipt} -F guest-egress
    ${ipt} -A guest-egress -d ${dns} -p udp --dport 53 -j RETURN
    ${ipt} -A guest-egress -d ${dns} -p tcp --dport 53 -j RETURN
    ${lib.concatMapStrings (net: "${ipt} -A guest-egress -d ${net} -j REJECT\n") blocked}
    ${ipt} -D OUTPUT ${match} -j guest-egress 2>/dev/null || true
    ${ipt} -I OUTPUT 1 ${match} -j guest-egress
  '';
  egressStop = ipt: ''
    ${ipt} -D OUTPUT ${match} -j guest-egress 2>/dev/null || true
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
