# The `dot` command, for a profile: the admin's (apply, inspect, maintain and bootstrap machines from
# the checkout) or the standard users' (their tools, getting more without root, dev shells, help).
# Both share lib.sh, the help topics and the dev-shell layers (nix/dot/devshell); this adds each
# one's built-in topics and docs. The home layer installs the one for the user's profile
# (home/modules/dot); the root flake's `dot` is the admin's, for `dot bootstrap`.
# tend: vg-dotfiles/Composition/dot
{ lib, pkgs, profile ? "admin", repoDefault ? "" }:
let
  topic = title: file: { inherit title; text = ""; file = null; path = "${file}"; };
  devshells = topic "Dev shells: a project's tools without installing anything (dot devshell)" ./docs/devshells.md;
  topics = {
    admin = {
      inherit devshells;
      dotfiles = { title = "vg-dotfiles: the machines, the profiles and how they fit (README)"; text = ""; file = "README.md"; path = "${../../README.md}"; };
      bootstrap = {
        title = "Setting up a new machine";
        text = ''
          On a fresh install (flakes aren't on yet, so the first command asks for them):
            nix --extra-experimental-features "nix-command flakes" run github:vaibhav-gopal/vg-dotfiles#dot -- bootstrap <host>
          or from a checkout: nix develop (same flag), then dot bootstrap <host>. Every step checks first, so
          re-run it whenever; `dot bootstrap --help` lists the options. New machine? Add it to
          nix/flake.nix's configurations and give it nix/<platform>/<host> first (dot help dotfiles).
        '';
        file = null; path = null;
      };
    };
    standard = {
      inherit devshells;
      account = topic "Your account: password, git identity, Claude, your own shell settings" ./docs/account.md;
    };
  }.${profile};

  share = pkgs.runCommand "dot-share" { } ''
    mkdir -p $out
    cp ${pkgs.writeText "topics.json" (builtins.toJSON topics)} $out/topics.json
    cp -r ${./devshell} $out/devshell
  '';
in
pkgs.writeShellApplication {
  name = "dot";
  runtimeInputs = with pkgs; [ coreutils gnugrep gnused gawk findutils jq glow git util-linux ];
  text = ''
    DOT_PROFILE="${profile}"
    DOT_SHARE="${share}"
    ${lib.optionalString (profile == "admin") "DOT_REPO_DEFAULT=${lib.escapeShellArg repoDefault}"}
    ${builtins.readFile ./lib.sh}
    ${builtins.readFile (if profile == "admin" then ./admin.sh else ./standard.sh)}
    main "$@"
  '';
  meta.description = "vg-dotfiles' dot command (${profile})";
}
