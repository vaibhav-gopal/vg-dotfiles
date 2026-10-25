# entry of the NixOS-WSL home layer: its modules, then the host's own overrides (the admin's only).
# tend: vg-dotfiles/NixOS-WSL
{ lib, hostname, ...}:
{
  imports = [
    ./modules
    (import ../admin-only.nix lib ./${hostname}) # the admin's own flips
  ];
}