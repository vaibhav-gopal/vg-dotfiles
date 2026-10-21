# vgsquid-jade (headless server, Tenstorrent Blackhole p150a, no GPU): flips and overrides the system module options for this machine.
# Same base hardware as vgsquid-azul and vgsquid-onyx; colleagues log in here with their own accounts.
# tend: vg-dotfiles/NixOS/vgsquid-jade
{ ... }:
{
  # manually add the systems hardware config!
  imports = [
    ./hardware-configuration.nix
  ];

  # Headless server: no desktop/GUI, OpenSSH on (see core/headless.nix); no GPU, so graphics stays off
  core.headless.enable = true;

  # sshd only over the tailnet: colleagues get this node shared to them from the Tailscale admin console
  core.headless.sshd.tailnetOnly = true;

  # Colleagues: name = [ "ssh-ed25519 AAAA... them@laptop" ]. Key login only, no sudo.
  core.headless.guests = {
  };

  # Tenstorrent Blackhole p150a: tt-kmd, tt-smi, tt-flash, 4x 1G hugepages
  modules.tenstorrent.enable = true;
  # LTS kernel: tt-kmd 2.7.0 doesn't build on linuxPackages_latest (7.3 dropped zap_vma_ptes)
  core.boot.kernel = "default";

  # Joins the tailnet as its own node `vgsquid-jade`
  modules.tailscale.enable = true;
}
