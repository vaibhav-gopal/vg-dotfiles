# Shared folders (profiles.shared): each is /srv/shared/<name>, for its members only (the group
# shared-<name>). New files and folders in it are writable by every member whatever their umask (a
# default ACL), and new folders keep the group (setgid). Guests stay isolated otherwise
# (core/isolation.nix): a shared folder is the one place they meet, and only the ones declared.
# tend: vg-dotfiles/NixOS/Core
{ config, lib, ... }:
let
  shares = lib.filterAttrs (_: members: members != [ ]) config.profiles.shared;
  group = name: "shared-${name}";
in {
  config = lib.mkIf (shares != { }) {
    assertions = lib.mapAttrsToList (name: members: {
      assertion = lib.all (u: config.profiles.users ? ${u}) members;
      message = "profiles.shared.${name}: ${lib.concatStringsSep ", " (lib.filter (u: !(config.profiles.users ? ${u})) members)} not in profiles.users";
    }) shares;

    users.groups = lib.mapAttrs' (name: members: lib.nameValuePair (group name) { inherit members; }) shares;

    systemd.tmpfiles.rules = [ "d /srv/shared 0755 root root -" ] ++ lib.concatLists (lib.mapAttrsToList (name: _: [
      "d /srv/shared/${name} 2770 root ${group name} -"
      # the group's rights on what's made inside, and the mask that would otherwise cut them to umask's
      "a+ /srv/shared/${name} - - - - default:group::rwx,default:mask::rwx,default:other::---"
    ]) shares);

    dot.help.shared = {
      title = "Shared folders: where you and others on this machine keep files together";
      text = lib.concatStrings (lib.mapAttrsToList (name: members: ''
        /srv/shared/${name}  ${lib.concatStringsSep ", " members}
      '') shares);
      file = "nix/nixos/modules/core/shared.md";
    };
  };
}
