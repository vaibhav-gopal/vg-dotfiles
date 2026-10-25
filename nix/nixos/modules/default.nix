# imports every NixOS system module.
# tend: vg-dotfiles/NixOS
{ ... }:
{
  imports = [
    # CORE MODULES
    ./core

    # OVERLAYS
    ./overlays

    # MODULES
    ./steam
    ./slurm
    ./tailscale
    ./tenstorrent
    ./vivaldi
  ];
}
