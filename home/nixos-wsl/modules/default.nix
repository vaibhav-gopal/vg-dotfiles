# imports every NixOS-WSL home module (none yet), and the NixOS-WSL defaults for the shared ones.
# tend: vg-dotfiles/NixOS-WSL
{ lib, ... }:

{
  imports = [
  ];

  # no desktop here: Windows runs the slideshow over its own clone (C:\vg-wallpapers)
  common.wallpapers.slideshow = lib.mkDefault false;
}
