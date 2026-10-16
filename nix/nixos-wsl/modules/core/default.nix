# WSL core: enables WSL and sets the user, hostname and state version.
# tend: vg-dotfiles/NixOS-WSL/Core
{ config, lib, username, hostname, version, ... }:
{
  imports = [
    ./env.nix
  ];

  system.stateVersion = version;
  wsl.enable = true;
  wsl.defaultUser = username;
  networking.hostName = hostname;
}
