{ ... }:
{
  imports = [
    # CORE MODULES
    ./core

    # OVERLAYS
    ./overlays

    # MODULES
    ./steam
    ./tailscale
    ./vivaldi
  ];
}
