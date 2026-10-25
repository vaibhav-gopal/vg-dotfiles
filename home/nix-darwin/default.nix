# entry of the nix-darwin home layer: its modules, then the host's own overrides (the admin's only).
# tend: vg-dotfiles/nix-darwin
{ lib, hostname, ...}:
{
  imports = [
    ./modules
    (import ../admin-only.nix lib ./${hostname}) # the admin's own flips
  ];
}