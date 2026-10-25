# What the admin `dot` evaluates on a machine's configuration: the flake's `dot.<host>` output is this
# applied to nixosConfigurations.<host> (or darwinConfigurations.<host>); parameters go in through
# `nix eval --apply`. Every row is flat and JSON-safe,
# so the shell side only formats it.
# tend: vg-dotfiles/Composition/dot
let
  inherit (builtins) attrNames concatLists concatStringsSep filter isAttrs isBool isFunction isList
    isString length match tryEval toJSON typeOf head;

  # a value, short enough for one line
  show = v:
    if isBool v then (if v then "true" else "false")
    else if v == null then "null"
    else if isFunction v then "<function>"
    else if isAttrs v && v ? outPath then (v.name or "<derivation>")
    else if isAttrs v then (if attrNames v == [ ] then "{ }" else "{ ${concatStringsSep " " (attrNames v)} }")
    else if isList v then
      (if v == [ ] then "[ ]" else "[ ${concatStringsSep " " (map (x: let r = tryEval (show x); in if r.success then r.value else "?") v)} ]")
    else if isString v then v
    else toJSON v;
  safe = f: let r = tryEval (f null); in if r.success then r.value else "<unset>";
  text = d: if isAttrs d then (d.text or "") else if d == null then "" else d;

  # every option under `opts`, flattened, with its value from `valueAt loc`. Home options' defaults
  # can need the user's own evaluation (their home directory), which the bare declarations lack and
  # tryEval can't catch, so `evalDefaults` is off for them and only defaultText shows.
  rows = opts: valueAt: rowsWith { evalDefaults = true; } opts valueAt;
  rowsWith = { evalDefaults }: opts: valueAt:
    let
      walk = set: concatLists (map (n:
        let v = set.${n}; in
        if isAttrs v && (v._type or null) == "option" then [ (row v) ]
        else if isAttrs v && !(v ? _type) then walk v
        else [ ]) (attrNames set));
      row = o: {
        path = concatStringsSep "." (loc o);
        type = o.type.description or "?";
        value = safe (_: show (valueAt o));
        default = if o ? defaultText then text o.defaultText else if evalDefaults && o ? default then safe (_: show o.default) else "";
        description = text (o.description or "");
      };
    in walk opts;

  # a home option's path, without the user type's <name>
  loc = o: if o.loc != [ ] && head o.loc == "<name>" then builtins.tail o.loc else o.loc;
  homeOpts = sys: sys.options.home-manager.users.type.getSubOptions [ ];
  at = loc: set: builtins.foldl' (s: k: s.${k}) set loc;
  under = path: set: if path == "" then set else at (builtins.filter isString (builtins.split "\\." path)) set;
in sys: {
  # system options under `path` ("" = this repo's: core and modules), with their values
  sysOptions = path:
    let roots = if path == "" then [ "core" "modules" "profiles" ] else [ path ]; in
    concatLists (map (p: rows (under p sys.options) (o: o.value)) roots);

  # home options under `path` ("" = this repo's), with `user`'s values
  homeOptions = path: user:
    let
      roots = if path == "" then [ "common" "nixtype" "features" "profile" ] else [ path ];
      opts = homeOpts sys;
      cfg = sys.config.home-manager.users.${user};
    in concatLists (map (p: if (tryEval (under p opts)).success then rowsWith { evalDefaults = false; } (under p opts) (o: at (loc o) cfg) else [ ]) roots);

  # every masked home feature (usrlib.mkProfileEnableOption) and whether it's on, per user
  features =
    let
      opts = homeOpts sys;
      ours = concatLists (map (p: if opts ? ${p} then rowsWith { evalDefaults = false; } opts.${p} (_: null) else [ ]) [ "common" "nixtype" "features" ]);
      masked = filter (r: match ".*profile\\.masks\\..*" r.default != null) ours;
      users = sys.config.profiles.users;
    in map (r: {
      inherit (r) path description;
      mask = head (match ".*profile\\.masks\\.([^`]*)`.*" r.default);
      on = builtins.mapAttrs (u: _: show (at (filter isString (builtins.split "\\." r.path)) sys.config.home-manager.users.${u})) users;
    }) masked;

  # who logs in: profile, logins, how many keys
  users = builtins.mapAttrs (u: p: {
    inherit (p) profile logins description;
    keys = length (sys.config.users.users.${u}.openssh.authorizedKeys.keys or [ ]);
  }) sys.config.profiles.users;

  # package names (system: environment.systemPackages; home: a user's home.packages)
  sysPkgs = map (p: p.pname or p.name) sys.config.environment.systemPackages;
  homePkgs = user: map (p: p.pname or p.name) sys.config.home-manager.users.${user}.home.packages;

  # a user's shell aliases and session variables
  session = user: {
    aliases = sys.config.home-manager.users.${user}.home.shellAliases;
    variables = builtins.mapAttrs (_: v: toString v) sys.config.home-manager.users.${user}.home.sessionVariables;
  };
}
