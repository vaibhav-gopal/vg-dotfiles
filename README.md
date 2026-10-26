# vg-dotfiles

The Nix side of Vaibhav's dotfiles: every NixOS, NixOS-WSL and nix-darwin machine, with a shared
home-manager layer. Windows has its own repo, vg-dotfiles-windows.

- One flake (`nix/flake.nix`) holds the table of machines; each platform's sub-flake builds them.
- Every module declares options (`core.*`, `modules.*`, `common.*`) and does nothing until a host
  turns it on; a host's folder only flips and overrides them.
- App config lives as raw files in a module's `*.d` folder, linked into place, so an edit applies
  without a rebuild.
- The design (why things are the way they are) is tracked in Tend: `tend design`.

## Machines

| Host | Archetype | What it is |
|---|---|---|
| `vgkraken` | nixos | Desktop: RX 7800 XT, Hyprland with Plasma as a fallback |
| `vgsquid-jade` | nixos | Tenstorrent Blackhole p150a box on an X870 board; GNOME at the console, colleagues over the tailnet |
| `vgsquid-azul`, `vgsquid-onyx` | nixos | Headless GPU-compute servers (RX 7800 XT): one X870, one TUF X670E-PLUS WIFI |
| `vgnixmini` | nixos | Plasma desktop |
| `vgwsl2` | nixos-wsl | NixOS under WSL2 on the Windows desktop |
| `vgmacbook` | nix-darwin | MacBook, with Homebrew for GUI apps |

## Folders

Every machine gets the same user-data tree as Windows (where it's `C:\vg-*`), in the home
directory: `~/vg-workspace/{projects,school,work}`, `~/vg-studio/{music,projects,samples,.scratch}`,
`~/vg-documents`, `~/vg-library`, `~/vg-tools/{bin,installers,licenses,standalone}`
(`common.folders`). Every machine also clones the machine repos beside `~/vg-dotfiles`:
`~/vg-paradigms`, `~/vg-deployments`, `~/vg-wallpapers` (private: HTTPS once `gh auth login` has
run, else SSH with the host's key). A missing one is cloned at the next rebuild; an existing one is
never pulled or reset (`git pull` is yours).

Desktops show `~/vg-wallpapers/wallpapers` as a shuffled slideshow, a new image every 30 minutes,
filling the screen (`common.wallpapers`): hyprpaper cycles the folder itself on Hyprland, Plasma's
own slideshow is pointed at it at login, and GNOME and macOS run `vg-wallpaper` (`vg-wallpaper pick`
shows what it would choose next).

## Claude Code

Every machine has two profiles, as on Windows: `claude` (personal, `~/.claude-personal`) and
`claude-work` (`~/.claude-work`); each clears `CLAUDE_CODE_OAUTH_TOKEN` so one profile's token never
reaches the other, and `claude` still follows a project's own `CLAUDE_CONFIG_DIR` (direnv). A host
that's only ever one of them sets `common.claude-code.profiles = [ "work" ];` (or `[ ]`);
`claude-profiles` shows which are logged in.

## Setting up a machine

Install the OS (NixOS, NixOS-WSL, or macOS with nix), then:

```bash
nix --extra-experimental-features "nix-command flakes" \
  run github:vaibhav-gopal/vg-dotfiles#dot -- bootstrap <host>   # e.g. vgsquid-jade
```

That clones the repo to `~/vg-dotfiles` (git comes with it). From a checkout, `nix develop` gives you
`dot`, then `dot bootstrap <host>`. It picks the archetype and runs its script in `nix/scripts/bootstrap/`
(`nixos.sh`, `nixos-wsl.sh`, `nix-darwin.sh`). Every step checks before it changes anything, so
re-run it whenever; it only does what's left:

1. **host**: the machine is in `nix/flake.nix` and of this archetype
2. **checkout**: the clone is at `~/vg-dotfiles` (where the config links point) and the right user runs it
3. **env**: writes `.env` for this host (an older one is kept as `.env.bak`)
4. **hardware** (NixOS): copies `/etc/nixos/hardware-configuration.nix` into `nix/nixos/<host>/` and
   stages it in git; an existing one that differs is kept unless `--regen-hardware`
5. **homebrew** (nix-darwin, `--with-homebrew`): installs Homebrew and adopts hand-installed casks
6. **system**: builds the system and applies it: `switch`, or `boot` when the kernel changes
   (NixOS) or the default user changes (NixOS-WSL); then reboot and re-run
7. **tailscale** (NixOS, `--with-tailscale`): `tailscale up` once tailscaled runs

Flakes are switched on for the bootstrap itself, so a fresh install needs no config first.
`--dry-run` checks and evaluates without changing anything; `dot bootstrap --help` lists the rest.
After the first build, commit the staged `hardware-configuration.nix`.

**NixOS-WSL:** a fresh distro logs in as `nixos`. The first run builds with `boot` and prints how
to restart the distro as your user; then clone again into that user's `~/vg-dotfiles` and re-run.

### Adding a machine

1. Add it to `configurations` in `nix/flake.nix` (username, system, hostname, `version` = the
   release it's installed with, `nixType`).
2. Create `nix/<archetype>/<host>/default.nix` and `home/<archetype>/<host>/default.nix`; on NixOS the
   system one imports `./hardware-configuration.nix` (the bootstrap copies it in).
3. Turn on what it needs (`core.*`, `modules.*`), then `dot bootstrap <host>` on the machine.

### Users and profiles

`profiles.users` in a host's `nix/<platform>/<host>/default.nix` is the one list of who logs in there.
The configuration's user is the **admin**: sudo, the full home layer linked live into this checkout,
and the host's own home folder (`home/<platform>/<host>`). Everyone else is **standard**: their own
account and home layer, no sudo, config files copied into the store (they can't read the checkout).

```nix
profiles.users.alex.logins = [ "ssh" ];           # or [ "console" "ssh" ]
core.headless.sshd.userKeys.alex = [ "ssh-ed25519 AAAA..." ];
```

- **Logins:** sshd admits only users with `ssh`; the tty and SDDM refuse those without `console`.
- **Passwords:** the admin's comes from the install. A standard user's first shell asks them to set
  one (`vg-first-password`, the one thing they may run as root, once).
- **What each profile gets:** each home feature has a mask, the profiles it's on for
  (`usrlib.mkProfileEnableOption`). Opinionated or personal features (folders and repo clones, zellij
  auto-start, kitty, Zed, the desktop apps, your git identity and Claude accounts) are admin-only;
  toolchains, Claude Code and `gh` are for everyone. A host changes a mask with
  `profiles.masks."term.zellij.auto_start" = [ "admin" "standard" ];`, and one user's own settings go in
  `profiles.users.<name>.home`.
- **Help:** a module sets `dot.help.<topic>` (inline `text`, a `.md` `file` in the repo, or both) inside
  its `mkIf enable`, so the topic comes and goes with it; system topics say whose `dot` shows them.

### Servers, and giving colleagues access

Headless hosts (`core.headless.enable`) run OpenSSH; with `core.headless.sshd.tailnetOnly` it is
reachable only over the tailnet.

- **Your key:** add it to `core.headless.sshd.authorizedKeys`; password login stays on until one is listed.
- **A colleague:** list them in `profiles.users` with their keys in `core.headless.sshd.userKeys`,
  rebuild, then share the node with them from the Tailscale admin console. With
  `core.headless.isolation.enable` they can't reach the tailnet or LAN from the host, see only their
  own processes and get a private `/tmp` (`nix/nixos/modules/core/isolation.nix`).

## Exports others read

`nix eval --json nix#configurations` (the machine table) and `nix#estate` (per host, the system services
it runs, from `estate.services` in the modules that turn them on) are read by Tend and the layers above
it. Their shape is a contract versioned by `nix#exports.version`: renaming or removing a field, or
changing what one means, bumps it (adding one doesn't), and `nix/scripts/tests/exports.test.sh` (in CI)
fails until it does.

## Day to day: `dot`

`dot` (in every user's home, and in `nix develop` here) works on this machine: `.env`'s host, else the
hostname (`DOT_HOST=<host>` for another). `dot help` lists the commands and the help topics.

| | |
|---|---|
| `dot apply [--boot]` | Rebuild and switch (`--boot`: from the next boot) |
| `dot diff` | Build, and show what changes against the running system |
| `dot update` | Bump `flake.lock` |
| `dot check [--all]` / `dot test` | Evaluate this machine (or every one) / run the test suite |
| `dot status` | Machine, generation, checkout |
| `dot users` / `dot features` | Who logs in here / which masked features each user has |
| `dot options [--home [--user u]] [path]` | Options with type, value and default (this repo's, or under a path) |
| `dot config [--home] <path>` / `dot pkgs` / `dot session` | A value as JSON / packages / aliases and variables |
| `dot user reset <name>` / `dot passwd` | A standard user's one-time password / yours (at the machine) |
| `dot gc [--all]`, `dot brew ...`, `dot cd`, `dot edit` | Housekeeping, Homebrew, the checkout |

Standard users get their own `dot`: `dot tools`, `dot find`, `dot shell <pkg>`, `dot devshell [template]`,
`dot whoami`, `dot passwd`, and the help topics of the features on the machine. Both are
`nix/dot/package.nix`; topics come from `dot.help` (see Users and profiles).

CI (`.github/workflows/check.yml`) evaluates every host, builds the shared home layer, runs the
profiles and exports tests, and runs shellcheck and the bootstrap, wallpaper and `dot` tests
(`bash nix/scripts/tests/<name>.test.sh`, or `dot test` for all of them). It also runs the NixOS VM
tests in `nix/nixos/tests`, the master flake's `checks` (`nix build -L ./nix#checks.x86_64-linux.isolation`:
a standard user on a shared host reaches the internet but not the LAN or the tailnet, from a shell, a
build or a container, and sees only their own processes and /tmp). They boot VMs, so `dot test` leaves
them out.

#### Imperative package installs

- Use nix profile to imperatively install packages instead through home-manager config



## Homebrew (nix-darwin only)

Homebrew covers what nix does poorly on macOS: GUI applications and Mac App Store
apps. CLI tooling still belongs in home-manager — see section 8 of `LEARN.md` for
the full decision order.

Managed by `modules.homebrew` in `nix/nix-darwin/modules/homebrew/default.nix`.

### One-time setup

nix-darwin manages Homebrew's *contents*, but does not install Homebrew itself.
Bootstrap it once (`dot bootstrap vgmacbook --with-homebrew` does the same before the first build):

```bash
dot brew bootstrap
```

That installs Homebrew if missing, then adopts any declared cask whose app is
already installed by hand (see *Migrating* below). It is idempotent - safe to
re-run. Then `dot apply`.

Until Homebrew exists, activation prints a red
`error: Homebrew is not installed, skipping...` and carries on harmlessly.

Related recipes:

| Recipe | Does |
|---|---|
| `dot brew bootstrap` | Install Homebrew, then adopt already-installed casks |
| `dot brew adopt` | Adoption pass on its own, without reinstalling anything |
| `dot brew check` | Report drift read-only, without changing anything |
| `dot brew file` | Print the declared Brewfile (works before any build) |

`dot brew check` is worth an occasional run because `dot apply` cannot fix either
kind of drift it reports. `brew bundle` trusts Homebrew's receipts: a cask whose
app you deleted still has a receipt, so the rebuild skips it rather than putting
it back, and an app installed by hand has no receipt to skip on. Anything marked
`DRIFT` is fixed by `dot brew adopt`.

The logic lives in `nix/scripts/homebrew.sh`. It evaluates the Brewfile from the
config rather than reading it out of the nix store, so it works before the first
build - which is exactly when bootstrapping happens.

### Usage

Declare everything in your host's darwin config (e.g. `nix/nix-darwin/vgmacbook/`):

```nix
modules.homebrew = {
  casks = [ "firefox" "spotify" ];       # GUI apps
  brews = [ ];                            # CLI formulae - prefer nix instead
  masApps = { "Pages" = 409201541; };     # Mac App Store, by numeric ID
  taps = [ ];                             # extra formula repositories
};
```

Then `dot apply`. Never `brew install` directly — see the guardrail below.

Find cask tokens with `brew search <name>`, and confirm what a token actually
installs with `brew info --cask <token>`.

### masApps

App Store apps cannot be casks, so anything App-Store-exclusive (Apple's own
apps, Safari extensions) goes here, keyed by numeric ID. Get the IDs for what is
already installed with:

```bash
nix run nixpkgs#mas -- list
```

`mas` itself needs no declaring — the nix-darwin module puts it on `PATH` during
activation. Caveats: you must be signed into the App Store, and `mas` can only
install apps already associated with that Apple ID.

Unlike casks, **already-installed App Store apps need no uninstall first** —
`brew bundle` checks the installed list and skips them, so declaring them just
records what is already there. The cleanup guardrail covers formulae, casks and
taps only; it does not uninstall App Store apps.

### The cleanup guardrail

`modules.homebrew.cleanup` defaults to `"zap"`. On every rebuild, any Homebrew
package **not** declared in the config is uninstalled, and for casks all
associated preference and application-support files are deleted too.

This makes the config the single source of truth, with two consequences:

- `brew install foo` is temporary — it will be reverted on the next rebuild.
  Add it to the config instead.
- It only touches things **Homebrew** installed. Apps installed manually by
  dragging a `.dmg` are invisible to brew and are left alone.

Set `cleanup = "uninstall"` to remove packages but keep their settings, or
`"none"` to disable the guardrail entirely.

### Migrating an already-installed app to a cask

Homebrew refuses to install a cask over an existing `.app` it did not install
(`It seems there is already an App at ...`). Two ways through it:

**Adopt (preferred).** Takes the existing app over in place, no re-download:

```bash
brew install --cask --adopt <token>
```

Do this once per already-installed app, before the first `dot apply` that
declares it. Adoption expects the installed version to match the cask's; on a
mismatch, update the app first or fall back to replacing it.

**Replace.** Move the app to the Trash, then declare the cask and rebuild.
Always works, but re-downloads the app and loses anything stored inside the
bundle.

Either way, once the app is brew-managed, later rebuilds are a no-op for it.
Migrate in small batches so a failure is easy to attribute.

### Aliases

| Alias | Does |
|---|---|
| `bcheck` | Is the system in sync with what's declared? |
| `bdrift` | Dry run: what's installed but NOT declared |
| `bls` | Everything currently installed |
| `bout` | What's outdated (incl. auto-updating casks) |
| `bup` | Deliberate `update && upgrade` |
| `bclean` | Manual `cleanup --prune=all` + `autoremove` |
| `bdoc` | `brew doctor` health check |
| `bfile` | View the generated Brewfile |

Defined in `home/nix-darwin/modules/homebrew`, not the system module - they are
home-manager `home.shellAliases` like every other alias in the repo, toggled
with `nixtype.homebrew.enable`. Inspect the merged set with:

```bash
dot session
```

### Background agents

Two launchd agents, both toggleable and rescheduleable via
`modules.homebrew.{cleanupAgent,updateAgent}`:

- `brew-cleanup` — Sundays 03:00, `cleanup --prune=all` + `autoremove`
- `brew-update` — daily 09:00, `brew update` only (metadata; never upgrades)

Both log to `~/Library/Logs/brew-{cleanup,update}.log`. Rebuilds never upgrade
anything, by design — upgrading is manual, via `bup`.

## Remote desktop (FreeRDP)

`common.freerdp` (home-manager, all platforms) installs `freerdp` and turns
each entry in `hosts` into an `rdp-<name>` alias for `sdl-freerdp`:

```nix
common.freerdp = {
  enable = true;
  defaultArgs = [ "/dynamic-resolution" "+clipboard" "/gfx:AVC444" ]; # shared
  hosts.vghydra = { user = "vaibhav"; app = true; };                  # -> rdp-vghydra
};
```

`host` defaults to the attribute name; `domain`, `extraArgs` and
`useDefaultArgs = false` are available per host. Passwords are never stored in
nix: the alias lets freerdp prompt.

### Dockable app (nix-darwin only)

`app = true` also produces `RDP <name>.app` in `~/Applications/Home Manager Apps`
(built by the generic `nixtype.apps` module), so it can live in the Dock. An
app launched from the Dock has no terminal to prompt in, so the launcher looks
the password up in the login Keychain first:

```bash
security add-generic-password -s rdp-<name> -a <user> -w   # prompts, one-time
```

- entry present → connects headless (`/p:` is on argv, so it is visible in
  `ps` on this Mac while the session runs)
- entry missing → opens the session in Ghostty and freerdp prompts as usual

Update or remove the entry with `security delete-generic-password -s rdp-<name>`
then re-add. The app itself is a plain `Info.plist` + bash launcher; anything
else can be wrapped the same way via `nixtype.apps.apps."<Name>".command`.
