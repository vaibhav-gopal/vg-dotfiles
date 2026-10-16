# imports every NixOS-WSL system module.
# tend: vg-dotfiles/NixOS-WSL
{ ... }:
{
  imports = [
    # CORE MODULES
    ./core

    # OVERLAYS
    ./overlays

    # MODULES
    ./tailscale
  ];
}
