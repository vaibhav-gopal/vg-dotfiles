# vgsquid-jade (headless server, Tenstorrent Blackhole p150a, no GPU): flips and overrides the system module options for this machine.
# X870 board (MediaTek MT7927 wifi 7); colleagues log in here with their own accounts.
# tend: vg-dotfiles/NixOS/vgsquid-jade
{ ... }:
{
  # the machine's hardware config (the bootstrap copies it in); imported once it exists, so the host
  # still evaluates before that (its `estate` services; a system build needs it)
  imports = builtins.filter builtins.pathExists [
    ./hardware-configuration.nix
  ];

  # Server profile (OpenSSH on, see core/headless.nix), with GNOME at the console on the CPU's integrated graphics
  core.headless.enable = true;
  core.login.enable = true;
  core.desktop.enable = true;
  core.desktop.sessions = [ "gnome" ];
  core.graphics.enable = true;
  core.graphics.amd.enable = true; # Ryzen iGPU (amdgpu); no discrete GPU

  # sshd only over the tailnet: colleagues get this node shared to them from the Tailscale admin console
  core.headless.sshd.tailnetOnly = true;

  # My own logins (key only from here on: password SSH turns off once a key is listed)
  core.headless.sshd.authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID2FsO6M1RRG5pCaYEJej7umAreRYVuNSiWDZ2+RWSDK vaibhav@vghydra"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ8q3ar8jmEBCUxLGgXU2CgTlivUv9nIkbNbbk8Y0BGA vaibhav@iphone-14-pro-max"
  ];

  # Who logs in here (I'm the admin, from the configuration): colleagues over ssh only, as standard
  # users; each also gets a Slurm association (modules.slurm) and the isolation below
  profiles.users = {
    yaxpatel.logins = [ "ssh" ];
    sameerjuin.logins = [ "ssh" ];
    siddhpatel.logins = [ "ssh" ];
  };

  # Their keys: name = [ "ssh-ed25519 AAAA..." ]. Key login only, no sudo
  # (the repo is public: keys go in without their email comments)
  core.headless.sshd.userKeys = {
    yaxpatel = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC+9kv47Xz056iKwY72jNH3VS3VlwmgVpa+gZy4LOp6T" ];
    sameerjuin = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHvW68NIUNs1iZpFVqa8krdwWhOI99DcTYfyUmD4MyVW" ];
    siddhpatel = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOqv/C//S5qW07M7/Mj7B2BnotUfcgOkvrvMmogum5QE" ];
  };

  # jade is my own tailnet node: guests can't reach the tailnet or LAN from it, see only their own
  # processes, and get private /tmp (core/isolation.nix); the tailnet reaches only sshd here
  core.headless.isolation.enable = true;

  # Tenstorrent Blackhole p150a: tt-kmd (2.11.0, builds on the latest kernel), tt-smi, 4x 1G hugepages
  modules.tenstorrent.enable = true;

  # Slurm schedules the cores and the card: the card is root-only outside a job, logins get 2 CPUs
  # and 8 GiB between them, fairshare from slurmdbd. Node line from `slurmd -C` on jade (Ryzen, 12 cores).
  modules.slurm = {
    enable = true;
    node = "CPUs=24 Boards=1 SocketsPerBoard=1 CoresPerSocket=12 ThreadsPerCore=2 RealMemory=63432";
  };

  # X870 board: MediaTek MT7927 wifi 7, which needs kernel 7.2+ (the default, latest)
  core.wireless.chip = "mt7927";

  # Joins the tailnet as its own node `vgsquid-jade`, shared to colleagues from the admin console.
  # No Tailscale SSH: it answers port 22 on the tailnet address and refuses shared-in users (no SSH
  # policy can match them), so everyone, me included, logs in through OpenSSH with a key.
  modules.tailscale = {
    enable = true;
    ssh = false;
  };
}
