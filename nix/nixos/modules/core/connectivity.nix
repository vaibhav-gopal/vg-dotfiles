# connectivity: internet, the board's wifi/bluetooth chip, bluetooth and printing.
# tend: vg-dotfiles/NixOS/Core
{ config, lib, usrlib, pkgs, ... }:
let
  cfginternet = config.core.internet;
  cfgwireless = config.core.wireless;
  cfgbluetooth = config.core.bluetooth;
  cfgprinting = config.core.printing;

  # MT7927 bluetooth firmware: btmtk asks for it, but linux-firmware doesn't ship it yet (MR !946 waits on
  # MediaTek's redistribution sign-off). Pinned to the MR author's commit and hash; drop this once
  # linux-firmware has mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin (a build collision will say so).
  mt7927-bt-firmware = pkgs.runCommand "mt7927-bt-firmware" {
    src = pkgs.fetchurl {
      url = "https://gitlab.com/jetm/linux-firmware/-/raw/77ad2a92acf2ac3e5ea47432b43d925ff99db909/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin";
      hash = "sha256-ZpxcmaDFnIXBKF09G4sxkVwtMTQaIkT07dy/1g/7vHY=";
    };
    meta.license = lib.licenses.unfree;
  } ''
    install -Dm444 $src $out/lib/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin
  '';
in {
  options.core.internet = {
    enable = usrlib.mkEnableOptionTrue "enable internet configuration";
    method = usrlib.mkEnumOption
      "Method to enable internet connection. (wpa_supplicant for non desktop environments)"
      "networkmanager"
      [ "networkmanager" "wpa_supplicant" ];
  };
  options.core.wireless = {
    # mt7927: MediaTek Filogic 380 (wifi 7 + BT 5.4) on the X870 boards; mt7922: MediaTek wifi 6E + BT 5.2 (AMD RZ616)
    chip = usrlib.mkEnumOption "The board's wifi/bluetooth chip (lspci -nn: 14c3:7927 or 14c3:6639 is mt7927, 14c3:0616 or 14c3:7922 is mt7922)" "none" [ "none" "mt7922" "mt7927" ];
  };
  options.core.bluetooth = {
    enable = usrlib.mkEnableOptionTrue "enable bluetooth configuration";
  };
  options.core.printing = {
    enable = usrlib.mkEnableOptionTrue "enable printing documents via CUPS";
  };

  config = lib.mkMerge [
    # Handle NetworkManager
    (lib.mkIf (cfginternet.enable && cfginternet.method == "networkmanager") {
      # Enable networking via networkmanager
      networking.networkmanager.enable = true;
    })
    # Handle wpa_supplicant
    (lib.mkIf (cfginternet.enable && cfginternet.method == "wpa_supplicant") {
      # Enables wireless support via wpa_supplicant.
      networking.wireless.enable = true;
    })

    # Both chips load their firmware from linux-firmware (core.boot turns on hardware.enableAllFirmware)
    (lib.mkIf (cfgwireless.chip != "none") {
      assertions = [{
        assertion = config.hardware.enableRedistributableFirmware;
        message = "core.wireless.chip = ${cfgwireless.chip} needs its firmware from linux-firmware: set hardware.enableRedistributableFirmware (core.boot does)";
      }];
    })
    # MT7927: mt7925e drives it from kernel 7.2 (wifi firmware in linux-firmware, ASPM turned off by the
    # driver itself); 6.18 LTS doesn't know the chip, so these hosts keep core.boot.kernel = "latest"
    (lib.mkIf (cfgwireless.chip == "mt7927") {
      assertions = [{
        assertion = lib.versionAtLeast config.boot.kernelPackages.kernel.version "7.2";
        message = "core.wireless.chip = mt7927 needs kernel 7.2 or later (mt7925e), not ${config.boot.kernelPackages.kernel.version}: use core.boot.kernel = \"latest\"";
      }];
      hardware.firmware = lib.mkIf cfgbluetooth.enable [ mt7927-bt-firmware ];
    })

    (lib.mkIf cfgbluetooth.enable {
      # Enable bluetooth
      hardware.bluetooth.enable = true;
      hardware.bluetooth.powerOnBoot = true;
      hardware.bluetooth.settings = {
        General = {
          Experimental = true; # Helps with newer BT protocols and implementations
        };
      };
      # Boot (load bluetooth kernel modules, explicitly)
      boot.kernelModules = ["btusb" "bluetooth"];
    })

    (lib.mkIf cfgprinting.enable {
      # Enable CUPS to print documents.
      services.printing.enable = true;
    })
  ];
}
