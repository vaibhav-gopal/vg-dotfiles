# Tailscale for NixOS: the host joins the tailnet as its own node, so it is
# reachable by MagicDNS name and can accept Tailscale SSH.
# First join is interactive: `sudo tailscale up --ssh`. After that the tailscaled-set
# service re-applies `tailscale set --ssh` at every boot, so the setting stays declarative.
# tend: vg-dotfiles/NixOS/Tailscale
{ config, lib, usrlib, ... }:
let
  cfg = config.modules.tailscale;
in {
  options.modules.tailscale = {
    enable = usrlib.mkEnableOptionFalse "Enable tailscaled on this host";
    ssh = usrlib.mkEnableOptionTrue "Advertise Tailscale SSH (`tailscale set --ssh`, applied at every boot)";
  };

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      # extraSetFlags, not extraUpFlags: nixpkgs only passes extraUpFlags when authKeyFile is set.
      # Both ways, so turning it off here also undoes an earlier `tailscale up --ssh`.
      extraSetFlags = [ "--ssh=${lib.boolToString cfg.ssh}" ];
    };

    # Trust traffic arriving over the tailnet.
    networking.firewall.trustedInterfaces = [ "tailscale0" ];

    estate.services = [{
      name = "tailscale";
      unit = "tailscaled.service";
      notes = "own tailnet node; Tailscale SSH ${if cfg.ssh then "on" else "off"}";
    }];
  };
}
