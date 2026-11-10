# headless server profile: desktop and peripheral defaults off, remote access (sshd) on, and kept up
# (core.headless.uptime): it never sleeps, blanks, dims or locks, whoever asks (GNOME at the console suspended jade under
# running jobs once: it counts only console input), Wi-Fi doesn't power-save, and a panic or a hang
# reboots it instead of leaving it stuck.
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
    uptime = {
      enable = usrlib.mkEnableOptionTrue "keep the server up: no sleep of any kind, no screen blanking, screensaver or lock, no Wi-Fi power saving, reboot after a panic or a hang";
      watchdog = usrlib.mkStringOption "Reboot through the hardware watchdog when systemd stops answering it for this long (\"off\": don't)" "60s";
    };
  };

  # Everything is mkDefault, so a host can still opt back in (e.g. `core.graphics.enable = true;` for a GPU compute box)
  config = lib.mkIf cfg.enable (lib.mkMerge [ {
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
  } (lib.mkIf cfg.uptime.enable {
    # every sleep refused at systemd, so no one can: GNOME's idle suspend, the greeter, a menu click
    systemd.sleep.settings.Sleep = {
      AllowSuspend = "no";
      AllowHibernation = "no";
      AllowHybridSleep = "no";
      AllowSuspendThenHibernate = "no";
    };
    services.logind.settings.Login = {
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
      HandleLidSwitch = "ignore";
      IdleAction = "ignore";
    };
    # and nothing idles at the console either: no GNOME sleep, dimming, blanking, screensaver or
    # lock, for every user, locked so no one's own settings bring it back
    programs.dconf.profiles.user.databases = lib.mkIf config.services.desktopManager.gnome.enable [{
      settings = {
        "org/gnome/settings-daemon/plugins/power" = {
          sleep-inactive-ac-type = "nothing";
          sleep-inactive-battery-type = "nothing";
          idle-dim = false;
        };
        "org/gnome/desktop/session".idle-delay = lib.gvariant.mkUint32 0;
        "org/gnome/desktop/screensaver" = {
          idle-activation-enabled = false;
          lock-enabled = false;
        };
        "org/gnome/desktop/lockdown".disable-lock-screen = true;
      };
      locks = [
        "/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type"
        "/org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type"
        "/org/gnome/settings-daemon/plugins/power/idle-dim"
        "/org/gnome/desktop/session/idle-delay"
        "/org/gnome/desktop/screensaver/idle-activation-enabled"
        "/org/gnome/desktop/screensaver/lock-enabled"
        "/org/gnome/desktop/lockdown/disable-lock-screen"
      ];
    }];
    # the login screen's X server: no screensaver blanking, no DPMS standby/off
    services.xserver.serverFlagsSection = lib.mkIf config.services.xserver.enable ''
      Option "BlankTime" "0"
      Option "StandbyTime" "0"
      Option "SuspendTime" "0"
      Option "OffTime" "0"
    '';
    boot.kernelParams = [ "consoleblank=0" ]; # the text console never blanks
    networking.networkmanager.wifi.powersave = lib.mkIf config.networking.networkmanager.enable false;
    # a panic reboots after 10 s; a hang (systemd stops answering the hardware watchdog) too. Out of
    # memory (a user's share, a job's) kills a process, never the machine: 0 is the kernel's
    # default, said here because NixOS's test VMs set 2 (any OOM panics) and the VM test fills a
    # user's share on purpose
    boot.kernel.sysctl."kernel.panic" = 10;
    boot.kernel.sysctl."vm.panic_on_oom" = 0;
    systemd.settings.Manager.RuntimeWatchdogSec = lib.mkIf (cfg.uptime.watchdog != "off") cfg.uptime.watchdog;
  }) ]);
}
