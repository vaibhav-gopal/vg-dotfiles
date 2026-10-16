# vgnixmini: flips and overrides the system module options for this machine.
# tend: vg-dotfiles/NixOS/vgnixmini
{ ... }:
{
  # manually add the systems hardware config!
  imports = [
    ./hardware-configuration.nix
  ];
}
