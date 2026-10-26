# NixOS sub-flake: inputs and the system configurations for the NixOS hosts.
# tend: vg-dotfiles/NixOS
{
  description = "NixOS configuration for Vaibhav Gopal";

  inputs = {
    # CORE INPUTS
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # EXTRA INPUTS
    claude-code.url = "github:sadjow/claude-code-nix";
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, home-manager, claude-code, ...  }:
  let
    specialArgsFor = conf: (
      let
        # Common nixpkgs configurations (overlays, unfree packages, etc...) (applies to all except `pkgs` / `nixpkgs` itself ; which you configure in the actual submodules using nixos options)
        commonPkgsConfig = {
          inherit (conf) system;
          config.allowUnfree = true;
        };

        # the base `pkgs` argument is special, it is automatically created / configured and passed in (DO NOT modify, outside of sub modules, many other non-user made modules use this configuration option!)
        # Need to set any other nixpkgs channel / input other than the main one (used to create system config) explicitly here (options DO NOT get passed into submodules)
        pkgs-unstable = import nixpkgs-unstable commonPkgsConfig;
      in
        # pass in: flake inputs // current system configuration // extra nixpkgs channels
        inputs // conf // { inherit pkgs-unstable; }
    );

    # every NixOS host is these modules and then its own folder; the VM tests' machines are these too
    baseModules = rootSelf: [
      #################CORE#################
      # home-manager includes
      home-manager.nixosModules.home-manager

      # core modules
      rootSelf.nixosModules.usrlib
      rootSelf.nixosModules.home
      rootSelf.nixosModules.profiles
      rootSelf.nixosModules.nix
      rootSelf.nixosModules.estate
      ./modules
    ];
  in {
    # make the nixos configuration factory function
    mkNixos = { rootSelf, configurations, ... }: (
      let
        nixosConfigs = nixpkgs.lib.filterAttrs (_: conf: conf.nixType == "nixos") configurations;
        genHost = name: conf: nixpkgs.lib.nixosSystem {
          inherit (conf) system; # inherit system > tells which specific `pkgs` / `nixpkgs` version to use
          specialArgs = specialArgsFor conf; # pass in specialArgs into every sub module

          modules = baseModules rootSelf ++ [
            #################USER#################
            ./${name} # automatically looks for a folder named after configuration name
          ];
        };
      in
        nixpkgs.lib.mapAttrs genHost nixosConfigs
    );

    # the NixOS VM tests (./tests), for the master flake's `checks`
    mkChecks = { rootSelf, ... }: {
      x86_64-linux.isolation = import ./tests/isolation.nix {
        inherit nixpkgs specialArgsFor;
        modules = baseModules rootSelf;
      };
    };

    # make the home-manager configuration factory function
    mkHome = { rootSelf, configurations, ... }: (
      let
        nixosConfigs = nixpkgs.lib.filterAttrs (_: conf: conf.nixType == "nixos") configurations;
        genHome = name: conf: home-manager.lib.homeManagerConfiguration (
        let
          commonPkgsConfig = {
            inherit (conf) system;
            config.allowUnfree = true;
          };
          pkgs = import nixpkgs commonPkgsConfig;
          pkgs-unstable = import nixpkgs-unstable commonPkgsConfig;
          extraSpecialArgs = inputs // conf // { inherit pkgs pkgs-unstable; };
        in {
          inherit pkgs extraSpecialArgs;

          modules = [
            #################CORE#################
            rootSelf.homeModules.home
            rootSelf.nixosModules.usrlib
          ];
        });
      in
        nixpkgs.lib.mapAttrs genHome nixosConfigs
    );
  };
}