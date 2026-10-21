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

  # Wifi: azul and onyx are one X870 (MT7927) and one TUF X670E-PLUS WIFI (wifi 6E), which is which isn't
  # known yet; both work on the latest kernel. Set core.wireless.chip from `lspci -nn` after install.

  # Joins the tailnet as its own node `vgsquid-azul`
  modules.tailscale.enable = true;
}
