# home-manager as a system module: the shared home layer for every user in profiles.users, each
# with their own profile, the host's masks and their own overrides.
# tend: vg-dotfiles/Shared
{ config, lib, usrlib, specialArgs, username, homedirectory, ... }:
let
  cfg = config.core.home;
  home = name: if name == username then homedirectory else config.users.users.${name}.home;
in {
  options.core.home = {
    enable = usrlib.mkEnableOptionTrue "enable home-manager configuration";
  };

  config = lib.mkIf cfg.enable {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    # the user's name and home come per user (below), not from the configuration's
    home-manager.extraSpecialArgs = removeAttrs specialArgs [ "username" "homedirectory" ] // { inherit usrlib; };
    home-manager.backupFileExtension = "backup-before-home-manager";
    home-manager.users = lib.mapAttrs (name: user: {
      imports = [ ../../home/default.nix user.home ];
      _module.args = { username = name; homedirectory = home name; };
      profile.name = user.profile;
      profile.masks = config.profiles.masks;
    }) config.profiles.users;
  };
}
