# the wallpaper slideshow (common.wallpapers) on the NixOS desktops: Plasma's own slideshow and a
# GNOME loop, each started at login by an XDG autostart entry only that desktop runs. Hyprland starts
# its loop from hypr.d/autostart.conf, with the rest of its session.
# tend: vg-dotfiles/Home/wallpapers
{ config, lib, ... }:
let
  cfg = config.common.wallpapers;

  autostart = desktop: exec: {
    "autostart/vg-wallpaper-${lib.toLower desktop}.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Wallpaper slideshow (vg-wallpapers)
      Exec=${exec}
      OnlyShowIn=${desktop};
      NoDisplay=true
      X-GNOME-Autostart-enabled=true
    '';
  };
in {
  config = lib.mkIf cfg.slideshow {
    xdg.configFile =
      autostart "KDE" "vg-wallpaper plasma"
      // autostart "GNOME" "vg-wallpaper loop gnome";
  };
}
