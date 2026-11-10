# the user-data folders every machine shares with vg-dotfiles-windows (~/vg-workspace, ~/vg-studio, ...
# where Windows has C:\vg-*), and the machine repos (vg-paradigms, vg-deployments, vg-wallpapers)
# cloned beside this repo's checkout, as Windows clones them beside its own.
# tend: vg-dotfiles/Home/folders
{ config, lib, pkgs, usrlib, ... }:
let
  cfg = config.common.folders;
  home = config.home.homeDirectory;

  # Clone-only: a missing repo is cloned, an existing one is never pulled or reset, so work in it is
  # never clobbered (`git pull` is the user's). All are private: HTTPS through gh's credentials first,
  # then SSH with the user's key. Not at activation: that runs as a system service, outside the
  # session, where gh's keyring token can't be read. `vg-repos` runs at login instead (a user service,
  # in the session) and never prompts; `vg-repos --interactive` (`dot repos`, the end of `dot
  # bootstrap`) logs gh in first when it has to.
  repos = pkgs.writeShellApplication {
    name = "vg-repos";
    runtimeInputs = [ pkgs.git pkgs.gh pkgs.openssh pkgs.coreutils ];
    text = ''
      interactive=0
      [[ "''${1:-}" == --interactive ]] && interactive=1
      # nothing may prompt unless asked: a desktop session's SSH_ASKPASS (GNOME's seahorse) pops a
      # password dialog even with GIT_TERMINAL_PROMPT=0
      if (( ! interactive )); then
        unset SSH_ASKPASS GIT_ASKPASS SSH_ASKPASS_REQUIRE
        export GIT_TERMINAL_PROMPT=0
      fi
      missing=0
      while read -r name url; do
        dir="$HOME/$name"
        [[ -d "$dir/.git" ]] && continue
        if (( interactive )) && ! gh auth status >/dev/null 2>&1; then
          echo "$name is private: log gh in first"
          gh auth login --git-protocol https
        fi
        ssh_url="git@github.com:''${url#https://github.com/}"
        if git clone --quiet "$url" "$dir" 2>/dev/null \
          || GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" git clone --quiet "$ssh_url" "$dir" 2>/dev/null; then
          echo "cloned $name"
        else
          echo "$name not cloned (gh auth login, or an SSH key on GitHub; then vg-repos --interactive)" >&2
          missing=1
        fi
      done <<'LIST'
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: u: "${n} ${u}") cfg.repos)}
      LIST
      exit "$missing"
    '';
  };
in {
  options.common.folders = {
    enable = usrlib.mkProfileEnableOption config "folders" "Create the shared user-data folders and clone the machine repos" [ "admin" ];
    # The same tree as vg-dotfiles-windows' home.psd1 `folders`, relative to the home directory
    dirs = usrlib.mkListOfStringsOption "Folders created (if missing) under the home directory" [
      "vg-documents/receipts"
      "vg-library/drivers"
      "vg-studio/.scratch"
      "vg-studio/music"
      "vg-studio/projects"
      "vg-studio/samples"
      "vg-tools/bin"
      "vg-tools/installers"
      "vg-tools/licenses"
      "vg-tools/standalone"
      "vg-workspace/projects"
      "vg-workspace/school"
      "vg-workspace/work"
    ];
    # Project repos are deliberately not here: projects start blank
    repos = usrlib.mkAttrsOption "Repos cloned (if missing) to ~/<name>, beside the vg-dotfiles checkout: name = HTTPS URL" {
      vg-paradigms = "https://github.com/vaibhav-gopal/vg-paradigms.git"; # the baseline (Tend's home)
      vg-deployments = "https://github.com/vaibhav-gopal/vg-deployments.git";
      vg-wallpapers = "https://github.com/vaibhav-gopal/vg-wallpapers.git"; # images in wallpapers/
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation = {
      vgFolders = lib.hm.dag.entryAfter [ "writeBoundary" ]
        (lib.concatMapStringsSep "\n" (d: ''run mkdir -p "${home}/${d}"'') cfg.dirs);
    };

    home.packages = [ repos ];
    # at login, in the session (where gh's token is); a repo it can't clone yet waits for the next one
    systemd.user.services.vg-repos = lib.mkIf pkgs.stdenv.isLinux {
      Unit.Description = "Clone the machine repos that are missing";
      Service = { Type = "oneshot"; ExecStart = "${repos}/bin/vg-repos"; SuccessExitStatus = [ 1 ]; };
      Install.WantedBy = [ "default.target" ];
    };
    launchd.agents.vg-repos = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = { ProgramArguments = [ "${repos}/bin/vg-repos" ]; RunAtLoad = true; };
    };

    dot.help.repos = {
      title = "The machine repos cloned beside the checkout (vg-repos)";
      text = ''
        ${lib.concatStringsSep ", " (lib.attrNames cfg.repos)} are cloned to ~/<name> when missing: at every login, and by
        `dot repos` (logs gh in first if it has to). A cloned repo is never pulled or reset.
      '';
    };
  };
}
