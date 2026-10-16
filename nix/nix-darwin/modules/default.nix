# imports every nix-darwin system module.
# tend: vg-dotfiles/nix-darwin
{ ...  }:
{
  imports = [
    # CORE MODULES
    ./core

    # OVERLAYS
    ./overlays

    # MODULES
    ./homebrew
    ./hotkeys
    ./statusbar
    ./yabai
  ];
}
