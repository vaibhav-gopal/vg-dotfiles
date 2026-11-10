# entry of the NixOS home layer: its modules, then the host's own overrides (the admin's only).
# tend: vg-dotfiles/NixOS
{ lib, hostname, ...}:
{
  imports = [
    ./modules
    (import ../admin-only.nix lib ./${hostname}) # the admin's own flips
  ];
}