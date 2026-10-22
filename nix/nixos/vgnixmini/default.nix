# vgnixmini: flips and overrides the system module options for this machine.
# tend: vg-dotfiles/NixOS/vgnixmini
{ ... }:
{
  # the machine's hardware config (the bootstrap copies it in); imported once it exists, so the host
  # still evaluates before that (its `estate` services; a system build needs it)
  imports = builtins.filter builtins.pathExists [
    ./hardware-configuration.nix
  ];
}
