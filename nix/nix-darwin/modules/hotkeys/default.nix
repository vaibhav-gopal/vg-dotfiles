# the skhd hotkey daemon and its shortcut config.
# tend: vg-dotfiles/nix-darwin
{ config, lib, usrlib, ... }:

let
  cfg = config.modules.hotkeys;
in {
  options.modules.hotkeys = {
    enable = usrlib.mkEnableOptionTrue "enable skhd hotkey daemon";
    config = usrlib.mkLinesOption "The skhd config (hotkey shortcuts)" '''';
  };

  config.services.skhd = lib.mkIf cfg.enable {
    enable = true;
    skhdConfig = cfg.config;
  };
}
