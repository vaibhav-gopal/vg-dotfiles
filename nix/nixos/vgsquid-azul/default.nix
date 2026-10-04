{ ... }:
{
  # manually add the systems hardware config!
  imports = [
    ./hardware-configuration.nix
  ];

  # Headless server: no desktop/GUI, OpenSSH on (see core/headless.nix)
  core.headless.enable = true;

  # Joins the tailnet as its own node `vgsquid-azul`
  modules.tailscale.enable = true;
}
