# zsh and bash (completion, suggestions, highlighting), direnv with nix-direnv, and the rc / profile fragments other modules add.
# tend: vg-dotfiles/Home/shell
{ config, lib, usrlib, ... }:

let
  cfg = config.common.shell;
in {
  options.common.shell = {
    enable = usrlib.mkEnableOptionTrue "Enable shell management and configuration";
    zsh = {
      zshrc = usrlib.mkLinesOption "Additional zshrc fragments to load" '''';
      zprofile = usrlib.mkLinesOption "Additional zprofile fragments to load" '''';
      zshenv = usrlib.mkLinesOption "Additional zshenv fragments to load" '''' ;
    };
    bash = {
      bashrc = usrlib.mkLinesOption "Additional bashrc fragments to load" '''' ;
      profile = usrlib.mkLinesOption "Additional profile fragments to load" '''';
    };
    direnv = {
      enable = usrlib.mkEnableOptionTrue "Enable direnv ; automatic loading of .envrc files for environment variables.";
      nix-direnv = {
        enable = usrlib.mkEnableOptionTrue "Enable nix-direnv ; automatic loading of env shells";
      };
    };
  };

  config = lib.mkIf cfg.enable ({
    # shell integration if not already enabled
    home.shell.enableShellIntegration = true;

    common.shell.zsh.zshrc = lib.mkMerge [
      ''
        source ${config.lib.dot.path "home/modules/shell/shell.d/hotkeys.zshrc"}
      ''
      # the user's own additions, which the managed rc files can't hold (they're rewritten on rebuild)
      (lib.mkAfter ''
        [ -r "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
      '')
    ];
    common.shell.bash.bashrc = lib.mkAfter ''
      [ -r "$HOME/.bashrc.local" ] && source "$HOME/.bashrc.local"
    '';
    programs.zsh = {
      enable = true;
      autocd = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      # zsh's files (and ~/.zsh_history) stay in the home directory on every host; 26.05's new
      # default (~/.config/zsh) would move them on the hosts installed on 26.05 only
      dotDir = config.home.homeDirectory;

      initContent = cfg.zsh.zshrc;
      profileExtra = cfg.zsh.zprofile;
      envExtra = cfg.zsh.zshenv;
    };

    programs.bash = {
      enable = true;
      enableCompletion = true;

      initExtra = cfg.bash.bashrc;
      profileExtra = cfg.bash.profile;
    };

    programs.direnv = lib.mkIf cfg.direnv.enable {
      enable = true; # automaticaly load in .envrc files into the current shell
      nix-direnv.enable = cfg.direnv.nix-direnv.enable; # automatically run nix develop and nix shell
    };
  });
}
