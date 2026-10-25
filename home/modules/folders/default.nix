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
  # then SSH with the host's key; neither may prompt during activation. A clone that can't happen yet
  # warns and leaves the rebuild alone; the next one tries again.
  cloneRepo = name: url: let
    dir = "${home}/${name}";
    ssh = lib.replaceStrings [ "https://github.com/" ] [ "git@github.com:" ] url;
  in ''
    if [ ! -d "${dir}/.git" ]; then
      if ! GIT_TERMINAL_PROMPT=0 run ${pkgs.git}/bin/git clone --quiet "${url}" "${dir}" 2>/dev/null \
        && ! GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" run ${pkgs.git}/bin/git clone --quiet "${ssh}" "${dir}" 2>/dev/null; then
        warnEcho "${name} not cloned (\`gh auth login\` or an SSH key on GitHub, then rebuild)"
      fi
    fi
  '';
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
      vgRepos = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ]
        (lib.concatStringsSep "\n" (lib.mapAttrsToList cloneRepo cfg.repos));
    };
  };
}
