# the accounts profiles.users describes: each standard user's account, where everyone may log in
# (sshd lets in only the users with ssh in their logins; tty and SDDM refuse those without
# console), and the first-login password: a standard user whose password was never set is asked
# for one when their shell starts (vg-first-password, the one thing they may run as root, and only
# for themselves, once). The admin's password comes from the install.
# tend: vg-dotfiles/NixOS/Core
{ config, lib, pkgs, ... }:
let
  users = config.profiles.users;
  standard = config.profiles.standard;
  withLogin = kind: lib.attrNames (lib.filterAttrs (_: u: lib.elem kind u.logins) users);
  noConsole = lib.subtractLists (withLogin "console") (lib.attrNames users);

  # pam_access for the console services: these users are refused there (ssh keeps its own list)
  consoleAccess = pkgs.writeText "access-console.conf" ''
    -:${lib.concatStringsSep " " noConsole}:ALL
  '';
  consoleRule = {
    control = "required";
    modulePath = "${pkgs.linux-pam}/lib/security/pam_access.so";
    args = [ "accessfile=${consoleAccess}" ];
    order = config.security.pam.services.login.rules.account.unix.order - 10;
  };

  firstPassword = pkgs.writeShellApplication {
    name = "vg-first-password";
    runtimeInputs = [ pkgs.shadow pkgs.gawk ];
    text = ''
      # Run through sudo by a standard user: sets their own password, only while none was ever set
      user="''${SUDO_USER:?run me with sudo}"
      case "$(passwd -S "$user" | awk '{print $2}')" in
        L | NP) exec passwd "$user" ;;
        *) echo "vg-first-password: $user already has a password; change it with passwd" >&2; exit 1 ;;
      esac
    '';
  };
in {
  config = {
    users.users = lib.mkMerge [
      (lib.genAttrs standard (name: {
        isNormalUser = true;
        inherit (users.${name}) description;
      }))
      (lib.mapAttrs (_: u: { inherit (u) linger; }) users)
    ];

    services.openssh.settings.AllowUsers = lib.mkIf config.services.openssh.enable (withLogin "ssh");

    security.pam.services = lib.mkIf (noConsole != [ ]) ({
      login.rules.account.access = consoleRule;
    } // lib.optionalAttrs config.services.displayManager.sddm.enable {
      sddm.rules.account.access = consoleRule;
    });

    environment.systemPackages = lib.optional (standard != [ ]) firstPassword;
    security.sudo.extraRules = lib.optional (standard != [ ]) {
      users = standard;
      commands = [{ command = "${firstPassword}/bin/vg-first-password"; options = [ "NOPASSWD" ]; }];
    };
    # the prompt, at the start of a standard user's interactive shell, until they've set one
    environment.interactiveShellInit = lib.mkIf (standard != [ ]) ''
      if [ -t 0 ] && [ "$(id -u)" -ge 1000 ] && ! id -nG | grep -qw wheel \
        && passwd -S "$(id -un)" 2>/dev/null | grep -qE '^\S+ (L|NP) '; then
        echo "First login: set your password (for the console and screen unlock)."
        sudo -n ${firstPassword}/bin/vg-first-password || true
      fi
    '';
  };
}
