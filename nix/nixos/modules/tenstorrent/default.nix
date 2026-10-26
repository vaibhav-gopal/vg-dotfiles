# Tenstorrent accelerators (Blackhole p150a and the like): the tt-kmd driver, tt-smi and tt-system-tools
# (what nixpkgs' hardware.tenstorrent installs, with a newer driver), plus the 1G hugepages the host
# runtime (tt-metal / UMD) maps.
# The driver's udev rule makes /dev/tenstorrent/* usable by every user, so no group is needed.
# tend: vg-dotfiles/NixOS/Tenstorrent
{ config, lib, pkgs, usrlib, ... }:
let
  cfg = config.modules.tenstorrent;

  # nixpkgs 26.05's tt-kmd 2.7.0 doesn't build on 7.2 or 7.3 (zap_vma_ptes); 2.11.0 does, so the
  # host can run the latest kernel. Used only while nixpkgs' is older.
  nixpkgsKmd = config.boot.kernelPackages.tt-kmd;
  tt-kmd = if lib.versionAtLeast nixpkgsKmd.version "2.11.0" then nixpkgsKmd else nixpkgsKmd.overrideAttrs {
    version = "2.11.0";
    src = pkgs.fetchFromGitHub {
      owner = "tenstorrent";
      repo = "tt-kmd";
      tag = "ttkmd-2.11.0";
      hash = "sha256-Wjxz8kfRNeq0CpGn0M4ro6XnuyyUyYFV1Y6sOGHzkA0=";
    };
  };
in {
  options.modules.tenstorrent = {
    enable = usrlib.mkEnableOptionFalse "Tenstorrent driver, tools and hugepages";
    # upstream's hugepages-setup (tt-system-tools) wants 4 per Blackhole or Wormhole card, 1 per Grayskull
    hugepages = usrlib.mkIntOption "1G hugepages reserved at boot for the cards (4 per Blackhole card)" 4;
    # the host's own pair, moved together: flash the firmware, then set both (dot help tenstorrent-firmware)
    firmware = usrlib.mkStringOption "The firmware bundle flashed on the cards (tt-smi: fw_bundle_version); empty if unknown" "";
    ttnn = usrlib.mkStringOption "The ttnn release built for that firmware (tt-metal's INSTALLING.md, per release): what new dev shells install; empty, the newest" "";
  };

  config = lib.mkIf cfg.enable {
    # hardware.tenstorrent's own lines, with the tt-kmd above (that module always takes the kernel's)
    boot.extraModulePackages = [ tt-kmd ];
    boot.kernelModules = [ "tenstorrent" ];
    services.udev.packages = [ tt-kmd ];
    # read by the dev shells' tenstorrent layer (nix/dot/devshell), which installs this ttnn
    environment.etc."tenstorrent/ttnn-version" = lib.mkIf (cfg.ttnn != "") { text = cfg.ttnn; };
    dot.help = {
      tenstorrent = {
        title = "The Tenstorrent card: what's installed, getting it, and the SDK (TT-NN)";
        text = ''
          Driver tt-kmd ${tt-kmd.version}, ${toString cfg.hugepages}x 1G hugepages, tt-smi and tt-burnin; the SDK goes in your project:
            dot devshell python tenstorrent      # a flake with ttnn in .venv
          ${lib.optionalString config.modules.slurm.enable "The card is open only inside a job: srun --gres=tt:1 -c 8 --mem=16G --pty bash"}
        '';
        file = "nix/nixos/modules/tenstorrent/tenstorrent.md";
      };
      tenstorrent-firmware = {
        title = "Updating the card's firmware (admin)";
        profiles = [ "admin" ];
        text = ''
          ttnn needs the firmware its release was built for (tt-metal's INSTALLING.md, per release). Here:
          firmware ${if cfg.firmware == "" then "(not set)" else cfg.firmware}, ttnn ${if cfg.ttnn == "" then "(not set: new dev shells take the newest)" else "${cfg.ttnn} (what new dev shells install)"}: modules.tenstorrent.firmware and .ttnn.
          Bundles: https://github.com/tenstorrent/tt-system-firmware/releases (fw_pack-<version>.fwbundle).
            curl -LO https://github.com/tenstorrent/tt-system-firmware/releases/download/v<version>/fw_pack-<version>.fwbundle
            # in your home (a job's /tmp is its own); tt-flash 4.1.0's `verify` is broken, `flash` works
            ${if config.modules.slurm.enable then "sbatch --gres=tt:1 -c 2 --mem=4G --wrap " else "sudo sh -c "}'nix shell nixpkgs#uv -c uvx --from tt-flash==4.1.0 tt-flash --no-tty flash fw_pack-<version>.fwbundle'
            ${lib.optionalString config.modules.slurm.enable "srun --gres=tt:1 "}tt-smi -s | grep fw_bundle_version   # then reboot, and check it again
          Nothing else may hold the card while it flashes; don't interrupt it. Then set both options and apply.
        '';
      };
    };

    estate.services = [{
      name = "tenstorrent";
      notes = "tt-kmd ${tt-kmd.version} kernel driver (/dev/tenstorrent/*, open to every user), ${toString cfg.hugepages}x 1G hugepages at /dev/hugepages-1G; tt-smi";
    }];

    # nixpkgs 26.05's tt-smi pins tt-tools-common==1.4.28 but ships 1.6.0, so its runtime-deps check fails the
    # build. pythonRelaxDeps doesn't reach it (the relax hook never runs before the check in this package), so
    # skip the check; `tt-smi --help` still imports cleanly against 1.6.0.
    nixpkgs.overlays = [
      (final: prev: {
        tt-smi = prev.tt-smi.overridePythonAttrs { dontCheckRuntimeDeps = true; };
      })
    ];

    # Reserved on the kernel command line: 1G pages are rarely free once memory has fragmented.
    boot.kernelParams = [ "hugepagesz=1G" "hugepages=${toString cfg.hugepages}" ];

    # The mount upstream ships as dev-hugepages\x2d1G.mount
    systemd.mounts = [{
      description = "Mount hugepages at /dev/hugepages-1G for Tenstorrent ASICs";
      what = "hugetlbfs";
      where = "/dev/hugepages-1G";
      type = "hugetlbfs";
      options = "pagesize=1G,mode=0777,nosuid,nodev";
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = "/sys/kernel/mm/hugepages/hugepages-1048576kB";
      };
      before = [ "sysinit.target" ];
      wantedBy = [ "sysinit.target" ];
    }];

    # No tt-flash: nixpkgs 26.05's needs pyluwen 0.8 but has 0.7.11 (a real API gap, not a pin), so
    # firmware updates go through PyPI's tt-flash, run with uvx (dot help tenstorrent-firmware).
    environment.systemPackages = [
      pkgs.tt-smi
      pkgs.tt-system-tools
      pkgs.tt-burnin # stress test
    ];
  };
}
