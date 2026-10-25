# the user this home layer is for: their profile (admin or standard), the masks that decide which
# features are on for each profile, the help topics their `dot` shows, and `config.lib.dot.source`,
# which links a config file live into the admin's checkout and copies it into the store for anyone
# else (they can't read the checkout).
# tend: vg-dotfiles/Home
{ config, lib, usrlib, ... }:
let
  cfg = config.profile;
  profiles = [ "admin" "standard" ];
  repo = ../..;
in {
  options.profile = {
    name = usrlib.mkEnumOption "This user's profile: admin (the one per machine, the full layer) or standard" "admin" profiles;
    isAdmin = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = cfg.name == "admin";
      description = "Whether this user is the machine's admin";
    };
    masks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf (lib.types.enum profiles));
      default = { };
      description = "Per feature (its mask name, e.g. term.zellij.auto_start): the profiles it's on for, overriding the feature's own default";
    };
  };

  options.dot.help = usrlib.mkHelpOption "Help topics `dot help` shows this user, from the features on for them (system topics: the host's dot.help)" { };

  config = {
    # rel: a path from the repo root, e.g. "home/modules/term/zellij.d". `source` is for a home
    # file's .source; `path` is the file's path as a string (to source it from a shell rc)
    lib.dot.source = rel:
      if cfg.isAdmin
      then config.lib.file.mkOutOfStoreSymlink "${config.extPaths.dotfilesDir}/${rel}"
      else repo + "/${rel}";
    lib.dot.path = rel:
      if cfg.isAdmin then "${config.extPaths.dotfilesDir}/${rel}" else "${repo + "/${rel}"}";

    xdg.configFile."dot/help.json".text = usrlib.helpJSON repo config.dot.help;
  };
}
