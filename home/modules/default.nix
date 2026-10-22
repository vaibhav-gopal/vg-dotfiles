# imports every shared home module.
# tend: vg-dotfiles/Home
{ ... }:
{
  imports = [
    # Core configuration
    ./core.nix

    # Features
    ./bun
    ./claude-code
    ./editor
    ./folders
    ./freerdp
    ./git
    ./java
    ./rustup
    ./shell
    ./ssh
    ./term
    ./wallpapers
  ];
}
