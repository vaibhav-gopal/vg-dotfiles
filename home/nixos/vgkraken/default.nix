{ pkgs-unstable, ...}:
{
  nixtype.hyprland.enable = true;

  # Chromium / Electron apps don't recognise Hyprland, so they would skip the keyring and keep
  # secrets in obfuscated plaintext ; point them at gnome-keyring (runs in both sessions here)
  nixtype.proton-pass.passwordStore = "gnome-libsecret";
  nixtype.vscode.package = pkgs-unstable.vscode.override { commandLineArgs = "--password-store=gnome-libsecret"; };
}
