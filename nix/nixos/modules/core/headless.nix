# headless server profile: desktop and peripheral defaults off, remote access (sshd) on.
# tend: vg-dotfiles/NixOS/Core
{ config, lib, usrlib, pkgs, username, ... }:
let
  cfg = config.core.headless;
  noKeys = cfg.sshd.authorizedKeys == [ ];
in {
  options.core.headless = {
    enable = usrlib.mkEnableOptionFalse "headless server profile: turn off desktop / GUI / peripheral defaults, turn on remote access";
    sshd = {
      enable = usrlib.mkEnableOptionTrue "enable the OpenSSH server";
      authorizedKeys = usrlib.mkListOfStringsOption "Public keys allowed to log in as the main user. Password login is allowed only while this is empty" [ ];
      tailnetOnly = usrlib.mkEnableOptionFalse "reach sshd only over the tailnet (tailscale0 is trusted): no firewall port on the LAN";
      # Other users' keys; their accounts come from profiles.users
      userKeys = usrlib.mkAttrsOption "Public keys for the other users in profiles.users, as `name = [ keys ]`" { };
    };
  };

  # Everything is mkDefault, so a host can still opt back in (e.g. `core.graphics.enable = true;` for a GPU compute box)
  config = lib.mkIf cfg.enable {
    core.login.enable = lib.mkDefault false;
    core.desktop.enable = lib.mkDefault false;
    core.graphics.enable = lib.mkDefault false;
    core.audio.enable = lib.mkDefault false;
    core.bluetooth.enable = lib.mkDefault false;
    core.printing.enable = lib.mkDefault false;
    core.mouse.enable = lib.mkDefault false;
    core.qmk.enable = lib.mkDefault false;
    core.env.fonts.enable = lib.mkDefault false;
    core.env.storage.packages = lib.mkDefault [
      pkgs.exfatprogs # provides: mkfs.exfat, ...
      pkgs.gptfdisk # provides: gdisk (GPT partition tables)
      # no gparted: GUI only
    ];

    modules.steam.enable = lib.mkDefault false;
    modules.vivaldi.enable = lib.mkDefault false;

    # OpenSSH: key-only once a key is listed; until then passwords work, so a fresh install is reachable
    services.openssh = lib.mkIf cfg.sshd.enable {
      enable = true;
      openFirewall = !cfg.sshd.tailnetOnly;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = lib.mkDefault noKeys;
        KbdInteractiveAuthentication = lib.mkDefault noKeys;
      };
    };
    # tailnet-only sshd still answers on tailscale0 when that interface isn't trusted
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = lib.mkIf (cfg.sshd.enable && cfg.sshd.tailnetOnly) [ 22 ];

    estate.services = lib.optional cfg.sshd.enable {
      name = "openssh";
      unit = "sshd.service";
      tailnet_only = cfg.sshd.tailnetOnly;
      notes = lib.concatStringsSep "; " ([
        (if noKeys then "password login until a key is listed" else "key login only")
      ] ++ lib.optional (config.profiles.standard != [ ]) "standard users (key only, no sudo): ${lib.concatStringsSep ", " config.profiles.standard}");
    };

    assertions = [{
      assertion = cfg.sshd.tailnetOnly -> config.modules.tailscale.enable;
      message = "core.headless.sshd.tailnetOnly needs modules.tailscale.enable, or sshd is unreachable";
    }] ++ map (name: {
      assertion = config.profiles.users ? ${name};
      message = "core.headless.sshd.userKeys.${name}: not a user in profiles.users";
    }) (lib.attrNames cfg.sshd.userKeys);

    users.users = lib.mkMerge [
      { ${username}.openssh.authorizedKeys.keys = cfg.sshd.authorizedKeys; }
      (lib.mapAttrs (_: keys: { openssh.authorizedKeys.keys = keys; }) cfg.sshd.userKeys)
    ];

    # enable running foreign binaries on NixOS (allows vscode server over Remote-SSH)
    programs.nix-ld.enable = lib.mkDefault true;
  };
}
