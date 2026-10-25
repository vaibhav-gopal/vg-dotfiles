# adminOnly <path>: a host's own home folder (home/<platform>/<host>) as a module that applies to the
# machine's admin only: it holds the admin's personal flips, which other users' masks decide for
# them. The folder may set config only (no imports or options), as host folders do.
# tend: vg-dotfiles/Home
lib: path:
let
  f = import path;
  fn = if lib.isFunction f then f else (_: f);
in
lib.setFunctionArgs
  (args: { config = lib.mkIf args.config.profile.isAdmin (fn args); })
  ((if lib.isFunction f then lib.functionArgs f else { }) // { config = false; })
