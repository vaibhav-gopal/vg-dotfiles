# the wallpaper slideshow over the vg-wallpapers clone (common.folders clones it): its settings, and
# `vg-wallpaper`, the script the desktops without a slideshow of their own run. Each platform wires
# it up (home/nixos/modules/wallpaper and hyprland, home/nix-darwin/modules/wallpaper); the same
# settings as Windows. Hyprland needs no script: hyprpaper 0.8 cycles a folder itself.
# tend: vg-dotfiles/Home/wallpapers
{ config, lib, pkgs, usrlib, ... }:
let
  cfg = config.common.wallpapers;

  # vg-wallpaper pick             print the image `next` would choose, changing nothing
  # vg-wallpaper next <desktop>   one new image: random, never the one showing
  # vg-wallpaper loop <desktop>   next, then again every `minutes`
  # vg-wallpaper plasma           point Plasma's own slideshow at the folder (it shuffles and times itself)
  # Every desktop scales to fill, cropping rather than letterboxing. VG_WALLPAPER_DIR overrides the
  # folder (the tests use it).
  script = pkgs.writeShellScriptBin "vg-wallpaper" ''
    set -uo pipefail
    # launchd and autostart give a bare PATH; the desktop's own tools (hyprctl, osascript) stay reachable
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.findutils pkgs.gnugrep ]}:$PATH"
    dir="''${VG_WALLPAPER_DIR:-${cfg.folder}}"
    state="''${XDG_STATE_HOME:-$HOME/.local/state}/vg-wallpaper"
    mkdir -p "$state"

    pick() { # a random image other than the last one shown (unless it's the only one)
      local last img; last="$(cat "$state/last" 2>/dev/null)"
      img="$(find "$dir" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | grep -vxF -- "$last" | shuf -n 1)"
      [ -n "$img" ] || img="$(find "$dir" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | shuf -n 1)"
      printf '%s' "$img"
    }

    set_image() { # set_image <desktop> <path>
      case "$1" in
        gnome)
          ${lib.optionalString pkgs.stdenv.isLinux ''
          ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-options zoom
          ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-uri "file://$2"
          ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-uri-dark "file://$2"''} ;;
        macos) /usr/bin/osascript -e "tell application \"System Events\" to tell every desktop to set picture to POSIX file \"$2\"" ;;
        *) echo "vg-wallpaper: unknown desktop $1" >&2; return 1 ;;
      esac
    }

    next() {
      local img; img="$(pick)"
      [ -n "$img" ] || { echo "vg-wallpaper: no images in $dir (is vg-wallpapers cloned?)" >&2; return 1; }
      set_image "$1" "$img" && printf '%s\n' "$img" >"$state/last"
    }

    case "''${1:-}" in
      pick) pick; echo ;;
      next) next "''${2:?desktop}" ;;
      loop)
        desktop="''${2:?desktop}"
        while :; do next "$desktop"; sleep ${toString (cfg.minutes * 60)}; done ;;
      plasma)
        ${lib.optionalString pkgs.stdenv.isLinux ''
        # systemd's busctl (on every NixOS machine) rather than Qt's qdbus, which would pull in Qt
        for _ in $(seq 30); do busctl --user status org.kde.plasmashell >/dev/null 2>&1 && break; sleep 1; done
        # SlideshowMode 0 = random; FillMode 2 = PreserveAspectCrop; SlideInterval in seconds
        busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s '
          desktops().forEach(function (d) {
            d.wallpaperPlugin = "org.kde.slideshow";
            d.currentConfigGroup = ["Wallpaper", "org.kde.slideshow", "General"];
            d.writeConfig("SlidePaths", "file://${cfg.folder}");
            d.writeConfig("SlideInterval", ${toString (cfg.minutes * 60)});
            d.writeConfig("SlideshowMode", 0);
            d.writeConfig("FillMode", 2);
          });' ''} ;;
      *) echo "usage: vg-wallpaper pick | next|loop <gnome|macos> | plasma" >&2; exit 2 ;;
    esac
  '';
in {
  options.common.wallpapers = {
    slideshow = usrlib.mkProfileEnableOption config "wallpapers.slideshow" "Run the desktop wallpaper as a shuffled slideshow over the vg-wallpapers clone" [ "admin" ];
    folder = usrlib.mkStringOption "The images (vg-wallpapers' contract: wallpapers/ holds images and nothing else)" "${config.home.homeDirectory}/vg-wallpapers/wallpapers";
    minutes = usrlib.mkIntOption "Minutes each image shows" 30;
    # for the platform modules that start it by path (launchd has no PATH to find it on)
    package = lib.mkOption { internal = true; readOnly = true; default = script; };
  };

  config = lib.mkIf cfg.slideshow {
    home.packages = [ script ];
  };
}
