# git with the user's identity, delta as its pager, tend's hook dispatcher for every repo, and the GitHub CLI.
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
    # tend's hook dispatcher for every repo: git's global core.hooksPath points at `dir`, where
    # `tend code hook --dispatcher <dir>` writes the hooks (each runs the repo's own .git/hooks/<event>,
    # then tend's checks where the repo has a .tend/). tend writes them, not nix: it isn't packaged here.
    tendHooks = {
      enable = usrlib.mkEnableOptionTrue "Point git's global core.hooksPath at tend's hook dispatcher";
      dir = usrlib.mkStringOption "Where tend's dispatcher hooks live (git's global core.hooksPath)" "${config.xdg.configHome}/git/hooks";
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
        } // lib.optionalAttrs cfg.tendHooks.enable {
          hooksPath = cfg.tendHooks.dir;
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

    # With core.hooksPath set, git reads no repo's .git/hooks itself: until tend has written the
    # dispatcher there, no hook runs anywhere, so every switch says so (writing it is the user's, once
    # per machine, with the tend they installed)
    home.activation.tendHooks = lib.mkIf cfg.tendHooks.enable
      (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -x ${lib.escapeShellArg "${cfg.tendHooks.dir}/pre-commit"} ]; then
          warnEcho ${lib.escapeShellArg "git's core.hooksPath is ${cfg.tendHooks.dir}, which has no hooks yet, so none run (each repo's own .git/hooks included). Write tend's dispatcher there: tend code hook --dispatcher ${cfg.tendHooks.dir}"}
        fi
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
