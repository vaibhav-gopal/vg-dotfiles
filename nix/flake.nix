# master flake: composes the NixOS, nix-darwin and NixOS-WSL sub-flakes into one set of machines.
# tend: vg-dotfiles/Composition
{
  description = "Master Flake Composition";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    # Local sub-flakes
    nixos-src.url = "path:./nixos";
    darwin-src.url = "path:./nix-darwin";
    wsl-src.url = "path:./nixos-wsl";
  };

  outputs = { self, nixpkgs, nixos-src, darwin-src, wsl-src, ... }: 
    let
      # attribute set of all configurations
      configurations = {
        vgkraken = {
          username = "vaibhav";
          system = "x86_64-linux";
          hostname = "vgkraken";
          version = "26.05"; # remember this is state version not nixpkgs version! (fresh install on 26.05)
          homedirectory = "/home/vaibhav";
          nixType = "nixos";
        };
        vgnixmini = {
          username = "vaibhav";
          system = "x86_64-linux";
          hostname = "vgnixmini";
          version = "25.11";
          homedirectory = "/home/vaibhav";
          nixType = "nixos";
        };
        vgsquid-azul = {
          username = "vaibhav";
          system = "x86_64-linux";
          hostname = "vgsquid-azul";
          version = "25.11";
          homedirectory = "/home/vaibhav";
          nixType = "nixos";
        };
        vgsquid-onyx = {
          username = "vaibhav";
          system = "x86_64-linux";
          hostname = "vgsquid-onyx";
          version = "25.11";
          homedirectory = "/home/vaibhav";
          nixType = "nixos";
        };
        vgsquid-jade = {
          username = "vaibhav";
          system = "x86_64-linux";
          hostname = "vgsquid-jade";
          version = "26.05"; # fresh install on 26.05
          homedirectory = "/home/vaibhav";
          nixType = "nixos";
        };
        vgwsl2 = {
          username = "vaibhav";
          hostname = "vgwsl2";
          system = "x86_64-linux";
          version = "25.11";
          homedirectory = "/home/vaibhav";
          nixType = "nixos-wsl";
        };
        vgmacbook = {
          username = "vaibhav";
          system = "aarch64-darwin";
          hostname = "vgmacbook";
          version = "25.11"; # remember this is state version not nixpkgs version!
          homedirectory = "/Users/vaibhav";
          nixType = "nix-darwin";
        };
      };

      baseArgs = { 
        inherit configurations;
        rootSelf = self;
      };
    in {
      # the machine table itself, so scripts can look a host up without evaluating its system
      # (nix/scripts/bootstrap reads its nixType and username before any hardware config exists)
      inherit configurations;

      # make all nixos configurations
      nixosConfigurations = (nixos-src.outputs.mkNixos baseArgs) // (wsl-src.outputs.mkNixos baseArgs);
      darwinConfigurations = (darwin-src.outputs.mkNixos baseArgs);

      # make all home-manager configurations 
      # -- NOTE: This should NOT be used for home-manager use! I know, why the fuck does it exist then? Purely for nix-eval so I can debug home-manager options! (see justfile)
      # -- It is MUCH more convenient to use home-manager as a nixos module instead, which is how its configured currently. (See the sub-flakes)
      # -- Hence, we do both!
      homeConfigurations = (nixos-src.outputs.mkHome baseArgs) // (wsl-src.outputs.mkHome baseArgs) // (darwin-src.outputs.mkHome baseArgs);

      # per host: the system services it runs (and where it's hosted), for Tend's estate:
      # `nix eval --json nix#estate` (modules/estate.nix ; a host without its hardware config yet still answers)
      estate = nixpkgs.lib.mapAttrs (_: sys: sys.config.estate.export)
        (self.nixosConfigurations // self.darwinConfigurations);

      # reusable modules ; use within sub-flakes by accessing rootSelf.nixosModules
      nixosModules = {
        usrlib = import ./modules/usrlib.nix;
        home = import ./modules/home.nix;
        nix = import ./modules/nix.nix;
        estate = import ./modules/estate.nix;
      };

      homeModules = {
        home = import ../home/default.nix;
      };
    };
}