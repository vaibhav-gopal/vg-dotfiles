# imports every nix-darwin home module.
# tend: vg-dotfiles/nix-darwin
{ ... }:

{
  imports = [
    # Features
    ./apps
    ./homebrew
    ./keyboard
    ./tailscale
    ./wallpaper
  ];
}
