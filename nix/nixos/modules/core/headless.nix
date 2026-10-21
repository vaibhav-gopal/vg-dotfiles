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
    };
    # Other people's accounts: name = [ their public keys ]. Key-only (no password), no sudo, no home-manager.
    guests = usrlib.mkAttrsOption "Guest accounts, as `name = [ public keys ]`: SSH key login only, no sudo" { };
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
    assertions = [{
      assertion = cfg.sshd.tailnetOnly -> config.modules.tailscale.enable;
      message = "core.headless.sshd.tailnetOnly needs modules.tailscale.enable, or sshd is unreachable";
    }];

    users.users = lib.mkMerge [
      { ${username}.openssh.authorizedKeys.keys = cfg.sshd.authorizedKeys; }
      # no password is ever set for a guest, so the key is the only way in
      (lib.mapAttrs (_: keys: {
        isNormalUser = true;
        openssh.authorizedKeys.keys = keys;
      }) cfg.guests)
    ];

    # enable running foreign binaries on NixOS (allows vscode server over Remote-SSH)
    programs.nix-ld.enable = lib.mkDefault true;
  };
}
