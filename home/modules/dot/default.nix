# `dot` for this user: the admin's or the standard one (nix/dot/package.nix), by profile; and, for
# `dot tools`, the list of what the home layer installed for them.
# tend: vg-dotfiles/Composition/dot
{ config, lib, pkgs, usrlib, ... }:
let
  cfg = config.common.dot;
  # home-manager's own plumbing, not tools anyone runs
  plumbing = n: lib.hasPrefix "dummy-" n || lib.elem n [ "hm-session-vars.sh" "home-configuration-reference-manpage" "shared-mime-info" ];
  tools = lib.filter (t: !plumbing t.name) (map (p: {
    name = p.pname or p.name;
    description = p.meta.description or "";
  }) config.home.packages);
in {
  options.common.dot = {
    enable = usrlib.mkEnableOptionTrue "Install `dot` (the admin's or the standard one, by profile)";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.callPackage ../../../nix/dot/package.nix {
        profile = config.profile.name;
        repoDefault = if config.profile.isAdmin then config.extPaths.dotfilesDir else "";
      })
    ];
    xdg.configFile."dot/tools.json".text = builtins.toJSON tools;
  };
}
