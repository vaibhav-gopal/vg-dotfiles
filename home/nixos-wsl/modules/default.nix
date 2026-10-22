# imports every NixOS-WSL home module (none yet), and the NixOS-WSL defaults for the shared ones.
# tend: vg-dotfiles/NixOS-WSL
{ lib, ... }:

{
  imports = [
  ];

  # no desktop here: Windows shows the wallpapers (its own clone in Pictures\vg-wallpapers)
  common.folders.wallpapers.enable = lib.mkDefault false;
}
