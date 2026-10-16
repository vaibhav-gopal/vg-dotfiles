# imports every NixOS home module.
# tend: vg-dotfiles/NixOS
{ ... }:

{
  imports = [
    ./discord
    ./headless
    ./hyprland
    ./minecraft
    ./proton-pass
    ./spotify
    ./vscode
  ];
}
