# entry of the nix-darwin home layer: its modules, then the host's own overrides.
# tend: vg-dotfiles/nix-darwin
{ hostname, ...}:
{
  imports = [
    ./modules
    ./${hostname}
  ];
}