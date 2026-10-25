# imports every shared home module.
# tend: vg-dotfiles/Home
{ ... }:
{
  imports = [
    # Core configuration
    ./core.nix
    ./profile.nix
    ./dot

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
