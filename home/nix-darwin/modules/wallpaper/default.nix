# the wallpaper slideshow (common.wallpapers) on macOS: a launchd agent sets a new random image at
# login and every `minutes` after; System Events applies it to every desktop, filling the screen.
# tend: vg-dotfiles/Home/wallpapers
{ config, lib, ... }:
let
  cfg = config.common.wallpapers;
in {
  config = lib.mkIf cfg.slideshow {
    launchd.agents.vg-wallpaper = {
      enable = true;
      config = {
        ProgramArguments = [ "${cfg.package}/bin/vg-wallpaper" "next" "macos" ];
        RunAtLoad = true;
        StartInterval = cfg.minutes * 60;
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/vg-wallpaper.log";
      };
    };
  };
}
