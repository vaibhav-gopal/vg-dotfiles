# vgkraken (desktop): flips and overrides the system module options for this machine.
# tend: vg-dotfiles/NixOS/vgkraken
{ pkgs-unstable, ... }:
{
  # manually add the systems hardware config!
  imports = [
    ./hardware-configuration.nix
  ];

  config = {
    # Hyprland as the daily driver, Plasma kept as a fallback session at the SDDM login screen
    core.desktop.sessions = [ "hyprland" "plasma" ];

    # use the keyring for saved logins (Chromium doesn't recognise Hyprland, see home/nixos/vgkraken)
    modules.vivaldi.package = pkgs-unstable.vivaldi.override { commandLineArgs = "--password-store=gnome-libsecret"; };

    # Radeon RX 7800 XT (RDNA3) ; open amdgpu + mesa, nothing proprietary
    core.graphics.amd = {
      enable = true;
      lact.enable = true; # fan curves / power limits / OC
      opencl.enable = true; # ROCm compute
    };

    # ISSUE:
    # bluetooth module (mt7925e - MediaTek Wifi 7 + Bluetooth 5.4)
    # getting boot messages / kernel messages with -110 error (failing enter/exit LP states)
    # prevents usb devices connected to the same bus from initializing immediately!!!

    # SOLVED:
    # literally just a windows dual boot issue ; need to do a full power cycle and capacitor discharge (everything)
    # disable hibernate + fast startup ; cold boot into nix immediately... should solve it

    # POSSIBLE FIXES (OLD):
    # disable ASPM (active state power management)
    # boot.kernelParams = [ "mt7925e.disable_aspm=1" ];
    # force btusb
    # boot.extraModprobeConfig = ''
    #   options btusb enable_autosuspend=0
    # '';
    # can also help with bluetooth issue ; related to how cpu handles memory mapping for usb devices
    # boot.kernelParams = [ "iommu=soft" ];
  };


}
