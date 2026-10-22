# what a machine runs, for Tend's estate (its Machine sources): each module that turns on a system
# service lists it here where it turns it on, and the flake's `estate` output reads the list per host
# (`nix eval --json nix#estate`) without building anything. Shared by NixOS, NixOS-WSL and nix-darwin.
# tend: vg-dotfiles/Shared
{ config, lib, ... }:
let
  cfg = config.estate;
  nullOr = t: lib.mkOption { type = lib.types.nullOr t; default = null; };
  service = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; description = "The service, as people call it (openssh, tailscale, ...)"; };
      kind = lib.mkOption { type = lib.types.str; default = "system"; description = "Tend's kind for it"; };
      unit = nullOr lib.types.str // { description = "Its systemd unit or launchd label, where it has one"; };
      tailnet_only = nullOr lib.types.bool // { description = "Reachable only over the tailnet"; };
      notes = nullOr lib.types.str // { description = "Anything about how it runs here worth knowing"; };
    };
  };
in {
  options.estate = {
    services = lib.mkOption {
      type = lib.types.listOf service;
      default = [ ];
      description = "System services this host runs; each module adds the ones it turns on";
    };
    hostedOn = nullOr lib.types.str // { description = "The machine this one runs inside (a WSL distro's Windows host)"; };
    # What the flake's `estate.<host>` output holds: the above as JSON-ready data, unset fields left out
    export = lib.mkOption {
      readOnly = true;
      internal = true;
      default = {
        services = map (s: lib.filterAttrs (_: v: v != null) s) cfg.services;
      } // lib.optionalAttrs (cfg.hostedOn != null) { hosted_on = cfg.hostedOn; };
    };
  };
}
