# entry of the NixOS home layer: its modules, then the host's own overrides.
# tend: vg-dotfiles/NixOS
{ hostname, ...}:
{
  imports = [
    ./modules
    ./${hostname}
  ];
}