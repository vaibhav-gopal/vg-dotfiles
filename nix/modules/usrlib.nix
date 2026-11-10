# usrlib: the mk*Option helpers every module declares its options with.
# tend: vg-dotfiles/Shared
{ lib, ... }:
{
  _module.args.usrlib = {
    mkEnableOptionTrue = desc: lib.mkEnableOption desc // { default = true; };
    mkEnableOptionFalse = desc: lib.mkEnableOption desc // { default = false; };
    # A home feature on for some profiles only: on by default when the user's profile is in its mask
    # (profile.masks.<mask> where the host sets one, else `profiles`). Opinionated features (keyboard
    # remaps, auto-starting things, personal accounts) mask to [ "admin" ].
    mkProfileEnableOption = config: mask: desc: profiles: lib.mkEnableOption desc // {
      default = lib.elem config.profile.name (config.profile.masks.${mask} or profiles);
      defaultText = lib.literalMD "on for the profiles in `profile.masks.${mask}`, else ${lib.concatStringsSep ", " profiles}";
    };
    # Help topics for `dot help`, set inside a feature's `mkIf enable` so they come and go with it.
    # A topic is inline `text`, a markdown `file` in the repo (a path from the repo root: the admin's
    # dot reads it live from the checkout, everyone else the store copy), or both (text first).
    # System topics also say whose `dot` shows them (`profiles`): a machine-wide module serves everyone.
    mkHelpOption = desc: { withProfiles ? false }: lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          title = lib.mkOption { type = lib.types.str; description = "One line: what the topic is about"; };
          text = lib.mkOption { type = lib.types.lines; default = ""; description = "Short help, inline (markdown)"; };
          file = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "A markdown file for the long form, as a path from the repo root"; };
        } // lib.optionalAttrs withProfiles {
          profiles = lib.mkOption {
            type = lib.types.listOf (lib.types.enum [ "admin" "standard" ]);
            default = [ "admin" "standard" ];
            description = "Whose `dot help` shows it";
          };
        };
      });
      default = { };
      description = desc;
    };
    # The JSON `dot` reads: each topic with its file's store copy (`path`) beside its repo path (`file`)
    helpJSON = repo: topics: builtins.toJSON (lib.mapAttrs (_: t: t // {
      path = if t.file == null then null else "${repo + "/${t.file}"}";
    }) topics);
    mkStringOption = desc: default: lib.mkOption {
      type = lib.types.str;
      default = default;
      description = desc;
    };
    mkIntOption = desc: default: lib.mkOption {
      type = lib.types.ints.unsigned;
      default = default;
      description = desc;
    };
    mkLinesOption = desc: default: lib.mkOption {
      default = default;
      type = lib.types.lines;
      description = desc;
    };
    mkPathOption = desc: default: lib.mkOption {
      type = lib.types.path;
      default = default;
      description = desc;
    };
    mkPackageOption = desc: default: lib.mkOption {
      type = lib.types.package;
      default = default;
      description = desc;
    };
    mkAttrsOption = desc: default: lib.mkOption {
      default = default;
      type = lib.types.attrsOf lib.types.anything;
      description = desc;
    };
    mkEnumOption = desc: default: list: lib.mkOption {
      type = lib.types.enum list;
      default = default;
      description = desc;
    };
    mkListOfEnumOption = desc: default: list: lib.mkOption {
      type = lib.types.listOf (lib.types.enum list);
      default = default;
      description = desc;
    };
    mkListOfStringsOption = desc: default: lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = default;
      description = desc;
    };
    mkNullOrStringOption = desc: default: lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = default;
      description = desc;
    };
    mkNullOrPathOption = desc: default: lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = default;
      description = desc;
    };
    mkListOfPackagesOption = desc: default: lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = default;
      description = desc;
    };
    mkNullOrPackageOption = desc: default: lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = default;
      description = desc;
    };
  };
}