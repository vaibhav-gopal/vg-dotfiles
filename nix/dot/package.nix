# The `dot` command, for a profile: the admin's (apply, inspect, maintain and bootstrap machines from
# the checkout) or the standard users' (their tools, getting more without root, dev shells, help).
# Both share lib.sh and read the same help topics; this adds each one's built-in topics, docs and,
# for standard users, the dev-shell templates. The home layer installs the one for the user's
# profile (home/modules/dot); the root flake's `dot` is the admin's, for `dot bootstrap`.
# tend: vg-dotfiles/Composition/dot
{ lib, pkgs, profile ? "admin", repoDefault ? "" }:
let
  topic = title: file: { inherit title; text = ""; file = null; path = "${file}"; };
  topics = {
    admin = {
      dotfiles = { title = "vg-dotfiles: the machines, the profiles and how they fit (README)"; text = ""; file = "README.md"; path = "${../../README.md}"; };
      bootstrap = {
        title = "Setting up a new machine";
        text = ''
          On a fresh install (flakes are switched on for you):
            nix run github:vaibhav-gopal/vg-dotfiles#dot -- bootstrap <host>
          or from a checkout: nix develop, then dot bootstrap <host>. Every step checks first, so
          re-run it whenever; `dot bootstrap --help` lists the options. New machine? Add it to
          nix/flake.nix's configurations and give it nix/<platform>/<host> first (dot help dotfiles).
        '';
        file = null; path = null;
      };
    };
    standard = {
      devshells = topic "Dev shells: a project's tools without installing anything" ./docs/devshells.md;
      account = topic "Your account: password, git identity, Claude, your own shell settings" ./docs/account.md;
    };
  }.${profile};

  share = pkgs.runCommand "dot-share" { } ''
    mkdir -p $out
    cp ${pkgs.writeText "topics.json" (builtins.toJSON topics)} $out/topics.json
    ${lib.optionalString (profile == "standard") ''
      mkdir -p $out/templates
      cp -r ${../../dev-utils/nix-examples/base} $out/templates/base
      cp -r ${../../dev-utils/nix-templates/python} $out/templates/python
    ''}
  '';
in
pkgs.writeShellApplication {
  name = "dot";
  runtimeInputs = with pkgs; [ coreutils gnugrep gnused findutils jq glow git util-linux ];
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
