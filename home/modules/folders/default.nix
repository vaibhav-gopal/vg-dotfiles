# the user-data folders every machine shares with vg-dotfiles-windows (~/vg-workspace, ~/vg-studio, ...
# where Windows has C:\vg-*), and the vg-wallpapers repo cloned into ~/Pictures.
# tend: vg-dotfiles/Home/folders
{ config, lib, pkgs, usrlib, ... }:
let
  cfg = config.common.folders;
  home = config.home.homeDirectory;
  wallpapersDir = "${home}/${cfg.wallpapers.path}";
in {
  options.common.folders = {
    enable = usrlib.mkEnableOptionTrue "Create the shared user-data folders in the home directory";
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
    wallpapers = {
      enable = usrlib.mkEnableOptionTrue "Clone the vg-wallpapers repo (private) if it's missing; never pulled by a rebuild";
      repo = usrlib.mkStringOption "The wallpaper repo, over HTTPS so gh's credentials clone it before the machine has an SSH key" "https://github.com/vaibhav-gopal/vg-wallpapers.git";
      path = usrlib.mkStringOption "Where it's cloned, under the home directory (images in its wallpapers/ folder)" "Pictures/vg-wallpapers";
    };
  };

  config = lib.mkIf cfg.enable {
    home.activation = {
      vgFolders = lib.hm.dag.entryAfter [ "writeBoundary" ]
        (lib.concatMapStringsSep "\n" (d: ''run mkdir -p "${home}/${d}"'') cfg.dirs);

      # A clone that can't happen yet (gh not logged in, offline) warns and leaves the rebuild alone;
      # the next one tries again. `git pull` in it brings new images.
      vgWallpapers = lib.mkIf cfg.wallpapers.enable (lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
        if [ ! -d "${wallpapersDir}/.git" ]; then
          run mkdir -p "$(dirname "${wallpapersDir}")"
          if ! GIT_TERMINAL_PROMPT=0 run ${pkgs.git}/bin/git clone --quiet "${cfg.wallpapers.repo}" "${wallpapersDir}"; then
            warnEcho "vg-wallpapers not cloned (log in with \`gh auth login\`, then rebuild)"
          fi
        fi
      '');
    };
  };
}
