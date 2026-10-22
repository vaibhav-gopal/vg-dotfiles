# Claude Code with isolated per-account profiles (one CLAUDE_CONFIG_DIR each) and their wrappers.
# tend: vg-dotfiles/Home/claude-code
{ config, lib, pkgs, usrlib, claude-code, ... }:
let
  cfg = config.common.claude-code;

  hasProfiles = cfg.profiles != [ ];
  hasDefault = cfg.defaultProfile != null;

  # Every path Claude Code resolves under ~/.claude relocates under CLAUDE_CONFIG_DIR,
  # so one directory per profile == one fully isolated account. ~/.claude-<name>, as on Windows
  # (vg-dotfiles-windows), so a session started on one machine is found on another with the same profile.
  profileDir = name: "${config.home.homeDirectory}/.claude-${name}";
  # where profiles lived before they followed Windows' names; moved at activation
  oldProfileDir = name: "${config.home.homeDirectory}/.local/share/claude-profiles/${name}";

  # force = true  -> always pin the profile (the named `claude-<name>` wrappers)
  # force = false -> only pin when unset, so a per-project direnv override still wins
  # Either way the OAuth token is cleared, so one profile's token never reaches the other.
  mkWrapper = { binName, profile, force }:
    pkgs.writeShellScriptBin binName ''
      set -euo pipefail
      ${if force
        then ''export CLAUDE_CONFIG_DIR="${profileDir profile}"''
        else ''export CLAUDE_CONFIG_DIR="''${CLAUDE_CONFIG_DIR:-${profileDir profile}}"''}
      unset CLAUDE_CODE_OAUTH_TOKEN
      mkdir -p "$CLAUDE_CONFIG_DIR"
      exec ${cfg.package}/bin/claude "$@"
    '';

  profilesCmd = pkgs.writeShellScriptBin "claude-profiles" ''
    echo "Active dir   : ''${CLAUDE_CONFIG_DIR:-<unset - default profile>}"
    echo
    ${lib.concatMapStringsSep "\n" (p: ''
      if [ -f "${profileDir p}/.credentials.json" ]; then
        echo "  ${p} (logged in)"
      else
        echo "  ${p} (not logged in - run: claude-${p})"
      fi
    '') cfg.profiles}
  '';
in {
  options.common.claude-code = {
    enable = usrlib.mkEnableOptionTrue "Enable Claude Code";
    package = usrlib.mkPackageOption "The Claude Code package to install"
      (claude-code.packages.${pkgs.stdenv.hostPlatform.system}.claude-code or pkgs.claude-code);
    alias = usrlib.mkStringOption "Optional shell alias for Claude Code (empty disables alias)" "";

    # Both on every machine; a host that's only ever one of them (a work-only server) lists just that, or none
    profiles = usrlib.mkListOfStringsOption
      "Isolated account profiles (CLAUDE_CONFIG_DIR = ~/.claude-<name>); each gets its own `claude-<name>` binary" [ "personal" "work" ];
    defaultProfile = usrlib.mkNullOrStringOption
      "Profile bound to the bare `claude` command (null installs the unwrapped binary); personal when it's a profile, else the first"
      (if lib.elem "personal" cfg.profiles then "personal" else if cfg.profiles != [ ] then lib.head cfg.profiles else null);
    sharedMemory = usrlib.mkNullOrPathOption
      "Optional CLAUDE.md linked read-only into every profile" null;
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = !hasDefault || lib.elem cfg.defaultProfile cfg.profiles;
      message = "common.claude-code.defaultProfile (${toString cfg.defaultProfile}) is not in common.claude-code.profiles.";
    }];

    # cfg.package ships bin/claude, so it is installed directly only when no
    # default-profile wrapper claims that name (otherwise: profile collision).
    home.packages =
      lib.optional (!hasDefault) cfg.package
      ++ map (p: mkWrapper { binName = "claude-${p}"; profile = p; force = true; }) cfg.profiles
      ++ lib.optional hasDefault
        (mkWrapper { binName = "claude"; profile = cfg.defaultProfile; force = false; })
      ++ lib.optional hasProfiles profilesCmd;

    home.shellAliases = lib.mkIf (cfg.alias != "") {
      ${cfg.alias} = "claude";
    };

    # Store symlinks are read-only, so only link files Claude Code never writes to.
    # settings.json / .credentials.json / plugins / transcripts stay writable.
    home.file = lib.mkIf (cfg.sharedMemory != null) (lib.listToAttrs (map (p: {
      name = "${lib.removePrefix "${config.home.homeDirectory}/" (profileDir p)}/CLAUDE.md";
      value.source = cfg.sharedMemory;
    }) cfg.profiles));

    # A profile still in the old place moves to ~/.claude-<name> (its login comes with it), then
    # every profile's dir exists. Never overwrites: if both exist, the old one is left for the user.
    home.activation = lib.mkIf hasProfiles {
      claudeProfileDirs = lib.hm.dag.entryAfter [ "writeBoundary" ]
        (lib.concatMapStringsSep "\n" (p: ''
          if [ -d "${oldProfileDir p}" ] && [ ! -e "${profileDir p}" ]; then
            run mv "${oldProfileDir p}" "${profileDir p}"
          fi
          run mkdir -p "${profileDir p}"
        '') cfg.profiles);
    };
  };
}
