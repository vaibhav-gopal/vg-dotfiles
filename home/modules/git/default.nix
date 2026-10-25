# git with the user's identity, delta as its pager, and the GitHub CLI.
# tend: vg-dotfiles/Home/git
{ config, lib, pkgs, usrlib, ... }:

let
  cfg = config.common.git;
in {
  options.common.git = {
    enable = usrlib.mkEnableOptionTrue "Enable git configuration management";
    # the admin's identity; other users set their own (`git config --global user.name ...`, ~/.gitconfig)
    name = usrlib.mkNullOrStringOption "Name for git config (null: not managed)" (if config.profile.isAdmin then "Vaibhav Gopal" else null);
    email = usrlib.mkNullOrStringOption "Email for git config (null: not managed)" (if config.profile.isAdmin then "vaibhav@gmail.com" else null);
    package = usrlib.mkPackageOption "The git package to use" pkgs.git;
    gh = {
      enable = usrlib.mkEnableOptionTrue "Enable the GH CLI";
      package = usrlib.mkPackageOption "The gh cli package to use" pkgs.gh;
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable Git with a default identity
    programs.git = {
      enable = true;

      settings = {
        # Default editor
        core = {
          editor = "nvim";
        };

        # pager.{diff,log,show,blame} come from programs.delta.enableGitIntegration below

        init.defaultBranch = "main";

        user = lib.filterAttrs (_: v: v != null) { inherit (cfg) email name; };
      };
    };

    # Without ~/.gitconfig, `git config --global` writes to the managed (read-only) ~/.config/git/config;
    # a user whose identity isn't managed gets an empty one of their own to write to
    home.activation.gitconfig = lib.mkIf (cfg.name == null || cfg.email == null)
      (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        [ -e "$HOME/.gitconfig" ] || run touch "$HOME/.gitconfig"
      '');

    # Use delta formatter for diffs
    programs.delta = {
      enable = true;
      enableGitIntegration = true;
    };

    # Enable GitHub CLI (gh)
    programs.gh = {
      enable = true;

      settings = {
        prompt = "enabled";
        git_protocol = "https";  # or "ssh" if you prefer
      };
    };

    # Git / Github Shell Aliases
    home.shellAliases = {
      gs = "git status";
      gl = "git log --oneline --graph --decorate";
    };
  };
}
