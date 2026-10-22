# Tailscale for NixOS-WSL: the distro joins the tailnet as its own node
# (separate from the Windows host), so it is reachable by MagicDNS name and
# can accept Tailscale SSH. First join is interactive: `sudo tailscale up --ssh`.
# After that the tailscaled-set service re-applies `tailscale set --ssh` at every boot.
# tend: vg-dotfiles/NixOS-WSL
{ config, lib, usrlib, ... }:
let
  cfg = config.modules.tailscale;
in {
  options.modules.tailscale = {
    enable = usrlib.mkEnableOptionFalse "Enable tailscaled in this WSL distro";
    ssh = usrlib.mkEnableOptionTrue "Advertise Tailscale SSH (`tailscale set --ssh`, applied at every boot)";
  };

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      # extraSetFlags, not extraUpFlags: nixpkgs only passes extraUpFlags when authKeyFile is set
      extraSetFlags = lib.optionals cfg.ssh [ "--ssh" ];
    };

    # Trust traffic arriving over the tailnet.
    networking.firewall.trustedInterfaces = [ "tailscale0" ];

    estate.services = [{
      name = "tailscale";
      unit = "tailscaled.service";
      notes = "own tailnet node, separate from the Windows host; Tailscale SSH ${if cfg.ssh then "on" else "off"}";
    }];
  };
}
