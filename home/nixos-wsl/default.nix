# entry of the NixOS-WSL home layer: its modules, then the host's own overrides.
# tend: vg-dotfiles/NixOS-WSL
{ hostname, ...}:
{
  imports = [
    ./modules
    ./${hostname}
  ];
}