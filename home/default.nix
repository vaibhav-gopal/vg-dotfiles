# entry of the shared home layer: the dotfiles paths, then the common modules and the platform's own.
# tend: vg-dotfiles/Home
{ config, usrlib, hostname, nixType, ... }:
let
  modulesPath = ./modules;
  nixtypePath = ./${nixType};

  # the one place the checkout's location is set ; every path below derives from it
  dir = config.extPaths.dotfilesDir;
in {
  # PATHS (read-only)
  options.extPaths = {
    # dotfiles global directories
    dotfilesDir = usrlib.mkPathOption "Where the vg-dotfiles repo is checked out, for use with raw symlinking / files out of nix store" "${config.home.homeDirectory}/vg-dotfiles";
    dotfilesEnvDir = usrlib.mkPathOption "The location of the dotfiles env directory, for use with raw symlinking / files out of nix store" "${dir}/env";
    dotfilesHomeDir = usrlib.mkPathOption "The location of the dotfiles home-manager directory, for use with raw symlinking / files out of nix store" "${dir}/home";

    # per-nixType + per-system overrides
    nixtypeDir = usrlib.mkPathOption "The location of the dotfiles home-manager, per-nixType overrides directory, for use with raw symlinking / files out of nix store" "${dir}/home/${nixType}";
    nixtypeSystemDir = usrlib.mkPathOption "The location of the dotfiles home-manager, per-nixType, per-system overrides directory, for use with raw symlinking / files out of nix store" "${dir}/home/${nixType}/${hostname}";

    # Module directories
    commonModulesDir = usrlib.mkPathOption "The location of the dotfiles home-manager common modules directory, for use with raw symlinking / files out of nix store" "${dir}/home/modules";
    nixtypeModulesDir = usrlib.mkPathOption "The location of the dotfiles home-manager, per-nixType modules directory, for use with raw symlinking / files out of nix store" "${dir}/home/${nixType}/modules";
  };

  # Expose parameterized features set and per-system overrides
  imports = [
    # Agnostic features
    modulesPath

    # Per nix-type overrides
    nixtypePath
  ];
}
