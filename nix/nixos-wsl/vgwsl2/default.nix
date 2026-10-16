# vgwsl2: flips and overrides the system module options for this machine.
# tend: vg-dotfiles/NixOS-WSL/vgwsl2
{ ... }:
{
  imports = [
  ];

  # Joins the tailnet as its own node `vgwsl2` (the Windows host is vghydra).
  modules.tailscale.enable = true;
}
