# vgsquid-azul (headless server): flips and overrides the system module options for this machine.
# tend: vg-dotfiles/NixOS/vgsquid-azul
{ ... }:
{
  # manually add the systems hardware config!
  imports = [
    ./hardware-configuration.nix
  ];

  # Headless server: no desktop/GUI, OpenSSH on (see core/headless.nix)
  core.headless.enable = true;

  # Radeon RX 7800 XT ; headless turns graphics off by default, keep it on for GPU compute (Vulkan via mesa RADV)
  core.graphics.enable = true;
  core.graphics.amd = {
    enable = true;
    lact.enable = true; # fan curves / power limits (`lact cli`, profiles applied by lactd at boot)
    opencl.enable = true; # ROCm compute
  };

  # Joins the tailnet as its own node `vgsquid-azul`
  modules.tailscale.enable = true;
}
