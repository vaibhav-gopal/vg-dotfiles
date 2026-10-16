{ config, lib, usrlib, pkgs, ... }:
let
  cfg = config.nixtype.hyprland;

  # live-editable configs: symlinked straight to the dotfiles checkout (hyprland, waybar and mako reload on save)
  link = name: config.lib.file.mkOutOfStoreSymlink "${config.extPaths.nixtypeModulesDir}/hyprland/${name}";
in {
  # MODULE OPTIONS DECLARATION
  options.nixtype.hyprland = {
    enable = usrlib.mkEnableOptionFalse "Enable the Hyprland desktop (configs + companion apps) ; pair with `core.desktop.sessions = [ \"hyprland\" ]` on the system side";
  };

  # MODULE BODY
  # NOTE: the compositor itself comes from the NixOS module (programs.hyprland, launched via UWSM).
  #       home-manager's wayland.windowManager.hyprland is deliberately unused: it would generate
  #       ~/.config/hypr/hyprland.conf and collide with the live-edited hypr.d symlink.
  config = lib.mkIf cfg.enable {
    home.packages = [
      # shell : bar, launcher / menus, notifications
      pkgs.waybar
      pkgs.fuzzel
      pkgs.mako
      pkgs.libnotify # notify-send

      # hypr* ecosystem : idle, wallpaper, colour picker, night light
      pkgs.hypridle
      pkgs.hyprpaper
      pkgs.hyprpicker
      pkgs.hyprsunset
      # polkit agent (password prompts for GUI apps) ; the binary lives in libexec, so put it on PATH
      (pkgs.writeShellScriptBin "hyprpolkitagent" ''exec ${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent "$@"'')

      # screenshots + clipboard history
      pkgs.grimblast
      pkgs.cliphist
      pkgs.wl-clipboard

      # hardware keys
      pkgs.brightnessctl
      pkgs.playerctl

      # TUIs the bar opens in floating kitty windows (network uses nmtui, shipped with networkmanager)
      pkgs.bluetui
      pkgs.wiremix

      # USB drives : automount + tray icon (needs services.udisks2 on the system side)
      pkgs.udiskie

      # looks : cursor + CJK glyphs for the kanji workspace labels
      pkgs.bibata-cursors
      pkgs.noto-fonts-cjk-sans
      # icons for GTK, Qt and fuzzel ; folders tinted "nordic", the closest papirus shade to kanagawa's dragonBlue
      (pkgs.papirus-icon-theme.override { color = "nordic"; })
      # Qt apps (Prism Launcher, KDE apps) : Fusion style + the kanagawa palette in qt6ct.d
      pkgs.qt6Packages.qt6ct
      # GTK3 apps (Thunar, pavucontrol) : the Adwaita-dark theme autostart.conf selects ; gtk3 itself ships no dark theme dir
      pkgs.gnome-themes-extra
    ];
    fonts.fontconfig.enable = true;

    xdg.configFile."hypr".source = link "hypr.d";
    xdg.configFile."waybar".source = link "waybar.d";
    xdg.configFile."fuzzel".source = link "fuzzel.d";
    xdg.configFile."mako".source = link "mako.d";
    xdg.configFile."qt6ct".source = link "qt6ct.d";

    # UWSM env: home-manager session variables for every session, plus hyprland-only extras
    xdg.configFile."uwsm/env".source = "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";
    xdg.configFile."uwsm/env-hyprland".source = link "uwsm.d/env-hyprland";

    # The Great Wave off Kanagawa (Hokusai, public domain) ; referenced by hypr.d/hyprpaper.conf
    home.file.".local/share/wallpapers/great-wave.jpg".source = pkgs.fetchurl {
      url = "https://upload.wikimedia.org/wikipedia/commons/a/a5/Tsunami_by_hokusai_19th_century.jpg";
      hash = "sha256-MMFwJg3jk/Ub1ZKtrMbwcUtg8VfAl0TpxbbUbmphNxg=";
    };
  };
}
