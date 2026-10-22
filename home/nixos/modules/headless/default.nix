# headless home profile: switches the GUI applications off by default.
# tend: vg-dotfiles/NixOS/Headless
{ config, lib, usrlib, ... }:
let
  cfg = config.nixtype.headless;
in {
  # MODULE OPTIONS DECLARATION
  options.nixtype.headless = {
    enable = usrlib.mkEnableOptionFalse "Headless server: turn off GUI applications (pair with core.headless on the system side)";
  };

  # MODULE BODY
  config = lib.mkIf cfg.enable {
    nixtype.discord.enable = lib.mkDefault false;
    nixtype.hyprland.enable = lib.mkDefault false;
    nixtype.minecraft.enable = lib.mkDefault false;
    nixtype.proton-pass.enable = lib.mkDefault false;
    nixtype.spotify.enable = lib.mkDefault false;
    nixtype.vscode.enable = lib.mkDefault false;

    common.wallpapers.slideshow = lib.mkDefault false; # no desktop to show it on
    common.term.kitty.enable = lib.mkDefault false;
    common.editor.zed.enable = lib.mkDefault false;
  };
}
