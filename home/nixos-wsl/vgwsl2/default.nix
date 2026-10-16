# vgwsl2: flips and overrides the home module options for this machine.
# tend: vg-dotfiles/NixOS-WSL/vgwsl2
{ ... }:
{
  # Same Claude Code accounts as vgmacbook.
  common.claude-code = {
    profiles = [ "personal" "work" ];
    defaultProfile = "personal";
  };
}
