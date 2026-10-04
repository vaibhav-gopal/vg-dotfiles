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
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = lib.mkDefault noKeys;
        KbdInteractiveAuthentication = lib.mkDefault noKeys;
      };
    };
    users.users.${username}.openssh.authorizedKeys.keys = cfg.sshd.authorizedKeys;

    # enable running foreign binaries on NixOS (allows vscode server over Remote-SSH)
    programs.nix-ld.enable = lib.mkDefault true;
  };
}
