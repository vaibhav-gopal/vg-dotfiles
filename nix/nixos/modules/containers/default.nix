# Containers for every user, rootless: Podman (with the docker command) and distrobox, for running
# another distro's userland (Ubuntu, mainly) or an application's image. Each user's containers and
# images live in their own home; nothing needs sudo on the host (inside a distrobox, sudo is the
# container's root, which is the user). Normal users get subordinate uid ranges by default, which
# rootless containers need. On a shared host, core/isolation.nix extends the guests' network rule to
# their containers.
# tend: vg-dotfiles/NixOS/Containers
{ config, lib, pkgs, usrlib, ... }:
let
  cfg = config.modules.containers;
in {
  options.modules.containers = {
    enable = usrlib.mkEnableOptionFalse "rootless Podman and distrobox for every user";
  };

  config = lib.mkIf cfg.enable {
    virtualisation.podman = {
      enable = true;
      dockerCompat = true; # `docker ...` runs podman
      defaultNetwork.settings.dns_enabled = true; # containers on one network find each other by name
    };
    environment.systemPackages = [ pkgs.distrobox pkgs.podman-compose ];

    dot.help.containers = {
      title = "Containers: another distro (distrobox) or an app's image (podman), without root";
      text = ''
        distrobox create -n ubuntu -i ubuntu:24.04 && distrobox enter ubuntu   # an Ubuntu shell, sudo inside
        podman run --rm -it docker.io/library/alpine sh                        # any image (`docker` works too)
        Everything is yours alone, under ~/.local/share/containers; nothing here needs host sudo.
      '';
      file = "nix/nixos/modules/containers/containers.md";
    };

    estate.services = [{
      name = "podman";
      notes = "rootless Podman (docker-compatible) and distrobox for every user";
    }];
  };
}
