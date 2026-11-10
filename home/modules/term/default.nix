# the terminal: kitty, zellij (starts with every shell), yazi and starship, each with its live-edited config.
# tend: vg-dotfiles/Home/term
{ config, lib, pkgs, usrlib, ... }:

let
  cfg = config.common.term;

  # zellij's copy_command on a local desktop: the session's clipboard (Wayland, else X11)
  zellijClip = pkgs.writeShellApplication {
    name = "zellij-clip";
    runtimeInputs = [ pkgs.wl-clipboard pkgs.xclip ];
    text = ''
      if [ -n "''${WAYLAND_DISPLAY:-}" ]; then exec wl-copy
      elif [ -n "''${DISPLAY:-}" ]; then exec xclip -selection clipboard
      else cat >/dev/null; echo "zellij-clip: no desktop session to copy to" >&2; exit 1
      fi
    '';
  };
  zellijLocalConfig = ''
    if [ -z "''${SSH_CONNECTION:-}" ] && { [ -n "''${WAYLAND_DISPLAY:-}" ] || [ -n "''${DISPLAY:-}" ]; } \
      && [ -r "''${XDG_CONFIG_HOME:-$HOME/.config}/zellij/config.kdl" ]; then
      _zc="''${XDG_RUNTIME_DIR:-$HOME/.cache}/zellij-local.kdl"
      { cat "''${XDG_CONFIG_HOME:-$HOME/.config}/zellij/config.kdl"; printf '\ncopy_command "zellij-clip"\n'; } >"$_zc"
      export ZELLIJ_CONFIG_FILE="$_zc"
      unset _zc
    fi
  '';
in {
  options.common.term = {
    enable = usrlib.mkEnableOptionTrue "Enable some terminal utilities";
    zellij = {
      enable = usrlib.mkEnableOptionTrue "Enable zellij the terminal multiplexer";
      enable_config = usrlib.mkEnableOptionTrue "Enable zellij config setup";
      package = usrlib.mkPackageOption "Default zellij package to use" pkgs.zellij;
      auto_start = usrlib.mkProfileEnableOption config "term.zellij.auto_start" "Enable zellij auto-start on shell start (shell-integration recommended)" [ "admin" ];
    };
    yazi = {
      enable = usrlib.mkEnableOptionTrue "Enable yazi the terminal file explorer";
      enable_config = usrlib.mkEnableOptionTrue "Enable yazi config setup";
      package = usrlib.mkPackageOption "Default yazi package to use" pkgs.yazi;
    };
    starship = {
      enable = usrlib.mkEnableOptionTrue "Enable starship the terminal prompt";
      enable_config = usrlib.mkEnableOptionTrue "Enable starship config setup";
      package = usrlib.mkPackageOption "Default starship package to use" pkgs.starship;
    };
    kitty = {
      enable = usrlib.mkProfileEnableOption config "term.kitty" "Enable kitty terminal emulator" [ "admin" ];
      enable_config = usrlib.mkEnableOptionTrue "Enable kitty config setup";
      package = usrlib.mkPackageOption "Default kitty package to use" pkgs.kitty;
    };
  };

  config = lib.mkIf cfg.enable {
    # zellij : terminal multiplexer
    programs.zellij = lib.mkIf cfg.zellij.enable {
      enable = true;
      package = cfg.zellij.package;
      attachExistingSession = false; # attach existing session when auto-start'ing zellij
      exitShellOnExit = false; # exit shell when exiting an auto-start'ed zellij session
    };
    xdg.configFile."zellij" = lib.mkIf (cfg.zellij.enable && cfg.zellij.enable_config) { source = config.lib.dot.source "home/modules/term/zellij.d"; };
    # zellij copies with OSC 52, which GNOME's terminals (VTE) ignore, so on a local desktop it copies
    # through the desktop's clipboard instead; over ssh it keeps OSC 52, which carries the copy back to
    # the terminal you came from. One config either way: a local session gets config.kdl plus
    # copy_command, written at shell start (so live edits apply), before zellij starts.
    home.packages = lib.mkIf (cfg.zellij.enable && pkgs.stdenv.isLinux) [ zellijClip ];
    common.shell.zsh.zshrc = lib.mkMerge [
      (lib.mkIf (cfg.zellij.enable && pkgs.stdenv.isLinux) (lib.mkBefore zellijLocalConfig))
      (lib.mkIf cfg.zellij.auto_start ''
        eval "$(zellij setup --generate-auto-start zsh)"
      '')
    ];
    common.shell.bash.bashrc = lib.mkMerge [
      (lib.mkIf (cfg.zellij.enable && pkgs.stdenv.isLinux) (lib.mkBefore zellijLocalConfig))
      (lib.mkIf cfg.zellij.auto_start ''
        eval "$(zellij setup --generate-auto-start bash)"
      '')
    ];

    # yazi : terminal file manager and viewer (enables lots of features, batch rename, archiving, trash bin, etc...)
    programs.yazi = lib.mkIf cfg.yazi.enable {
      enable = true;
      package = cfg.yazi.package;
      shellWrapperName = "y";
    };
    xdg.configFile."yazi" = lib.mkIf (cfg.yazi.enable && cfg.yazi.enable_config) { source = config.lib.dot.source "home/modules/term/yazi.d"; };

    # starship : terminal prompt
    programs.starship = lib.mkIf cfg.starship.enable {
      enable = true;
    };
    xdg.configFile."starship.toml" = lib.mkIf (cfg.starship.enable && cfg.starship.enable_config) { source = config.lib.dot.source "home/modules/term/starship.d/starship.toml"; };

    # kitty : terminal emulator (fairly simple, and barebones)
    programs.kitty = lib.mkIf cfg.kitty.enable {
      enable = true;
      package = cfg.kitty.package;
      extraConfig = ''
        include ./kitty_custom.conf
        shell ${pkgs.zsh}/bin/zsh
      '';
    };
    xdg.configFile."kitty/kitty_custom.conf" = lib.mkIf (cfg.kitty.enable && cfg.kitty.enable_config) { source = config.lib.dot.source "home/modules/term/kitty.d/kitty.conf"; };
    
    # Home shell aliases
    home.shellAliases = {
      z = lib.mkIf cfg.zellij.enable "zellij";
    };
  };
}
