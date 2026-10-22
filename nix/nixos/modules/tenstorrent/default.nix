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
  };

  config = lib.mkIf cfg.enable {
    # hardware.tenstorrent's own lines, with the tt-kmd above (that module always takes the kernel's)
    boot.extraModulePackages = [ tt-kmd ];
    boot.kernelModules = [ "tenstorrent" ];
    services.udev.packages = [ tt-kmd ];
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
    # firmware updates go through `uvx tt-flash` (uv is in the home tools) when needed.
    environment.systemPackages = [
      pkgs.tt-smi
      pkgs.tt-system-tools
      pkgs.tt-burnin # stress test
    ];
  };
}
