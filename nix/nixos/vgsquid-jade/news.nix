# What changed on vgsquid-jade, for the people who use it: each one's `dot` shows a note once, and
# `dot news` all of them (dot.news, nix/modules/profiles.nix). Add one when a change reaches them;
# the name is its id (never reuse one: whoever read it won't see it again).
# tend: vg-dotfiles/NixOS/vgsquid-jade
{ ... }:
{
  dot.news = {
    "2026-10-25-shared-folders" = {
      date = "2026-10-25";
      title = "Shared folders: /srv/shared/capstone and /srv/shared/everyone";
      text = "For keeping files together (log in again to get in): dot help shared";
      profiles = [ "standard" ];
    };
    "2026-10-25-help" = {
      date = "2026-10-25";
      title = "New help: dot help nix (installing and trying packages), dot help background";
      text = "background: keeping sessions, services and containers running after you log out";
      profiles = [ "standard" ];
    };
    "2026-10-25-ttnn-pin" = {
      date = "2026-10-25";
      title = "New Tenstorrent dev shells install ttnn 0.81.1, the one the card's firmware takes";
      text = "A project made before: uv pip install ttnn==0.81.1 (dot help tenstorrent)";
      profiles = [ "standard" ];
    };
  };
}
