# Prism Launcher for Minecraft.
# tend: vg-dotfiles/NixOS/Apps
{ config, lib, pkgs, usrlib, ... }:
let
  cfg = config.nixtype.minecraft;
in {
  # MODULE OPTIONS DECLARATION
  options.nixtype.minecraft = {
    enable = usrlib.mkProfileEnableOption config "minecraft" "Enable prism launcher for minecraft" [ "admin" ];
    package = usrlib.mkPackageOption "The prism launcher package for minecraft" pkgs.prismlauncher;
  };

  # MODULE BODY
  config = lib.mkIf cfg.enable {
    home.packages = [cfg.package];
  };
}
