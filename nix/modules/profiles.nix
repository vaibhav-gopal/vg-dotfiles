# profiles: the one place a host says who logs in, where, and as what. Exactly one admin, the
# configuration's own user (sudo, the full home layer linked live into the checkout, the admin
# `dot`); everyone else is `standard` (their own account and home layer, masked to what a non-admin
# user needs, and the standard `dot`). SSH keys stay with sshd (core.headless.sshd), not here.
# Every user gets the home layer (nix/modules/home.nix); a host's `dot.help` topics reach every
# user's `dot help` (/etc/dot/help.json), filtered by profile.
# tend: vg-dotfiles/Shared
{ config, lib, usrlib, username, nixType, ... }:
let
  cfg = config.profiles;
  profileNames = [ "admin" "standard" ];
  admins = lib.attrNames (lib.filterAttrs (_: u: u.profile == "admin") cfg.users);
in {
  options.profiles = {
    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          profile = usrlib.mkEnumOption "admin (only the configuration's user) or standard" "standard" profileNames;
          logins = usrlib.mkListOfEnumOption "Where this user may log in: console (a tty or the display manager) and ssh (with a key from core.headless.sshd)" [ "ssh" ] [ "console" "ssh" ];
          description = usrlib.mkStringOption "The user's full name" name;
          linger = usrlib.mkEnableOptionFalse "keep this user's services and containers running after they log out (systemd lingering)";
          home = lib.mkOption {
            type = lib.types.deferredModule;
            default = { };
            description = "This user's own home-manager settings, on top of the masks (e.g. a feature off just for them)";
          };
        };
      }));
      default = { };
      description = "Everyone who logs in to this machine. The configuration's user is the admin; list others as standard";
    };
    masks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf (lib.types.enum profileNames));
      default = { };
      description = "Per home feature (its mask name, e.g. term.zellij.auto_start): the profiles it's on for on this machine";
    };
    standard = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = lib.attrNames (lib.filterAttrs (_: u: u.profile == "standard") cfg.users);
      description = "The standard users (derived)";
    };
  };

  options.dot.help = usrlib.mkHelpOption "Help topics for this machine's `dot help`, set by the system modules that are on (Slurm's, for one)" { withProfiles = true; };

  config = {
    profiles.users.${username} = {
      profile = "admin";
      logins = lib.mkDefault [ "console" "ssh" ];
    };

    environment.etc."dot/help.json".text = usrlib.helpJSON ../.. config.dot.help;

    assertions = [
      {
        assertion = admins == [ username ];
        message = "profiles.users: the only admin is the configuration's user (${username}); found ${lib.concatStringsSep ", " admins}";
      }
      {
        assertion = cfg.standard == [ ] || nixType == "nixos";
        message = "profiles.users: standard users are only supported on NixOS hosts so far (this is ${nixType})";
      }
    ];
  };
}
