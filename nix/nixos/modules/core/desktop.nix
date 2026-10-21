# the login greeter and the desktop sessions it offers.
# tend: vg-dotfiles/NixOS/Core
{ config, lib, usrlib, pkgs, ... }:
let
  cfglogin = config.core.login;
  cfgdesktop = config.core.desktop;
in {
  options.core.login = {
    enable = usrlib.mkEnableOptionTrue "enable login session / greeter config (display manager, etc...)";
    select = usrlib.mkEnumOption "Chosen display manager" "sddm" [ "sddm" ];
  };
  options.core.desktop = {
    enable = usrlib.mkEnableOptionTrue "enable x11 windowing system and a desktop environment";
    sessions = usrlib.mkListOfEnumOption "Desktop environments / compositors to install ; each one becomes a session to pick at the login screen" [ "plasma" ] [ "plasma" "hyprland" "gnome" ];
  };

  config = lib.mkMerge [
    (lib.mkIf (cfglogin.enable && cfglogin.select == "sddm") {
      # Enable the simple desktop display manager (SDDM)
      services.displayManager.sddm.enable = true;
    })
    (lib.mkIf (cfgdesktop.enable && lib.elem "plasma" cfgdesktop.sessions) {
      # Enable the KDE Plasma Desktop Environment.
      services.desktopManager.plasma6.enable = true;
    })
    (lib.mkIf (cfgdesktop.enable && lib.elem "gnome" cfgdesktop.sessions) {
      # Enable the GNOME Desktop Environment ; SDDM stays the greeter, GNOME is one more session there
      services.desktopManager.gnome.enable = true;
      # gpg-agent is already the SSH agent (core/env.nix) ; don't let the keyring start a second one
      services.gnome.gcr-ssh-agent.enable = false;
      # plasma and gnome both set an ssh askpass ; with both installed, keep plasma's
      programs.ssh.askPassword = lib.mkIf (lib.elem "plasma" cfgdesktop.sessions) (lib.mkForce "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass");
    })
    (lib.mkIf (cfgdesktop.enable && lib.elem "hyprland" cfgdesktop.sessions) {
      programs.hyprland = {
        enable = true;
        withUWSM = true; # recommended ; launch with universal wayland session manager
        xwayland.enable = true;
      };

      # hyprlock authenticates through its own PAM service ; without it the lock screen can never unlock
      programs.hyprlock.enable = true;

      # dconf backs GTK settings (dark mode, cursor) outside of a full desktop environment
      programs.dconf.enable = true;

      # Electron / Chromium apps (vscode, discord, vivaldi) run as native wayland clients
      environment.sessionVariables.NIXOS_OZONE_WL = "1";

      xdg.portal = {
        enable = true;
        # hyprland: screensharing + screenshots ; gtk: file pickers (hyprland's portal has none)
        extraPortals = [ pkgs.xdg-desktop-portal-hyprland pkgs.xdg-desktop-portal-gtk ];
      };

      # keyring (Secret Service): where apps keep their own secrets (Proton Pass session, VS Code / browser logins)
      # unlocked by the SDDM login password, so it never prompts
      services.gnome.gnome-keyring.enable = true;
      security.pam.services.sddm.enableGnomeKeyring = true;
      # gpg-agent is already the SSH agent (core/env.nix) ; don't let the keyring start a second one
      services.gnome.gcr-ssh-agent.enable = false;

      # Thunar: graphical file manager next to yazi ; gvfs = trash + network shares, tumbler = thumbnails
      programs.thunar.enable = true;
      services.gvfs.enable = true;
      services.tumbler.enable = true;

      # USB drives: udisks2 mounts them, udiskie (started in hypr.d/autostart.conf) automates it
      services.udisks2.enable = true;
    })
    (lib.mkIf cfgdesktop.enable {
      # Enable the X11 windowing system.
      services.xserver.enable = true;
      # Configure keymap in X11
      services.xserver.xkb = {
        layout = "us";
        variant = "";
      };
    })
  ];
}