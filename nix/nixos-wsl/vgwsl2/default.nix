# vgwsl2: flips and overrides the system module options for this machine.
# tend: vg-dotfiles/NixOS-WSL/vgwsl2
{ username, ... }:
{
  imports = [
  ];

  # Joins the tailnet as its own node `vgwsl2` (the Windows host is vghydra).
  modules.tailscale.enable = true;

  # NixOS VM tests (other projects' `nix flake check`) run here on KVM: Windows exposes AMD-V through
  # .wslconfig's nestedVirtualization=true, and the user opens /dev/kvm through its group. Nix's
  # system-features already include kvm and nixos-test (the NixOS default).
  users.users.${username}.extraGroups = [ "kvm" ];

  # a WSL2 distro on the Windows desktop (vg-dotfiles-windows' VGHYDRA)
  estate.hostedOn = "vghydra";
}
