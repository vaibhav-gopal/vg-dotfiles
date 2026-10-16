# Proton Pass, wrapped so its Electron secret store backend can be chosen.
# tend: vg-dotfiles/NixOS/Apps
{ config, lib, pkgs, usrlib, ... }:
let
  cfg = config.nixtype.proton-pass;

  # Electron picks its secret store from the desktop it detects ; under Hyprland (or anything it doesn't
  # recognise) it silently falls back to "basic" (obfuscated plaintext), so the backend can be forced here.
  wrapped = pkgs.symlinkJoin {
    name = "proton-pass-${cfg.package.version}";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/proton-pass --add-flags "--password-store=${toString cfg.passwordStore}"
    '';
  };
in {
  # MODULE OPTIONS DECLARATION
  options.nixtype.proton-pass = {
    enable = usrlib.mkEnableOptionTrue "Enable the Proton Pass desktop app";
    package = usrlib.mkPackageOption "The Proton Pass package to use" pkgs.proton-pass;
    passwordStore = usrlib.mkNullOrStringOption "Force Electron's secret store (`gnome-libsecret`, `kwallet6`, ...) ; null lets Electron detect it from the desktop" null;
  };

  # MODULE BODY
  config = lib.mkIf cfg.enable {
    home.packages = [ (if cfg.passwordStore == null then cfg.package else wrapped) ];
  };
}
