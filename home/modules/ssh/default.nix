# ssh client configuration, with keep-alives on by default.
# tend: vg-dotfiles/Home/ssh
{ config, lib, pkgs, usrlib, ... }:

let
  cfg = config.common.ssh;
in {
  options.common.ssh = {
    enable = usrlib.mkEnableOptionTrue "Enable ssh configuration";
    package = usrlib.mkNullOrPackageOption "The ssh package to use ; if null, uses system package (was default)" pkgs.openssh;
    extraConfig = usrlib.mkLinesOption 
    "Extra configuration." 
    ''
      ServerAliveInterval 30
      ServerAliveCountMax 30
    '';
  };

  config = lib.mkIf cfg.enable {
    programs.ssh = {
      enable = true;
      package = cfg.package;
      extraConfig = cfg.extraConfig;

      # The old default config, spelled out as raw ssh_config settings (home-manager 26.05 deprecates
      # enableDefaultConfig and renames matchBlocks to settings)
      enableDefaultConfig = false;
      settings."*" = {
        ForwardAgent = false;
        AddKeysToAgent = "no";
        Compression = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
      };
    };
  };
}
