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

## Setting up a machine

Install the OS (NixOS, NixOS-WSL, or macOS with nix), then:

```bash
nix-shell -p git        # NixOS / NixOS-WSL: git isn't there on a fresh install
git clone https://github.com/vaibhav-gopal/vg-dotfiles.git ~/vg-dotfiles
cd ~/vg-dotfiles
./bootstrap.sh <host>   # e.g. ./bootstrap.sh vgsquid-jade
```

`bootstrap.sh` picks the archetype and runs its script in `nix/scripts/bootstrap/`
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
`--dry-run` checks and evaluates without changing anything; `./bootstrap.sh --help` lists the rest.
After the first build, commit the staged `hardware-configuration.nix`.

**NixOS-WSL:** a fresh distro logs in as `nixos`. The first run builds with `boot` and prints how
to restart the distro as your user; then clone again into that user's `~/vg-dotfiles` and re-run.

### Adding a machine

1. Add it to `configurations` in `nix/flake.nix` (username, system, hostname, `version` = the
   release it's installed with, `nixType`).
2. Create `nix/<archetype>/<host>/default.nix` and `home/<archetype>/<host>/default.nix`; on NixOS the
   system one imports `./hardware-configuration.nix` (the bootstrap copies it in).
3. Turn on what it needs (`core.*`, `modules.*`), then `./bootstrap.sh <host>` on the machine.

### Servers, and giving colleagues access

Headless hosts (`core.headless.enable`) run OpenSSH; with `core.headless.sshd.tailnetOnly` it is
reachable only over the tailnet.

- **Your key:** add it to `core.headless.sshd.authorizedKeys`; password login stays on until one is listed.
- **A colleague:** add `name = [ "ssh-ed25519 ..." ];` to `core.headless.guests` (key-only, no sudo),
  rebuild, then share the node with them from the Tailscale admin console.

## Day to day

`just` runs everything once `.env` exists (`just` alone lists the recipes):

- `just build`: rebuild and switch (`just buildboot` applies at the next boot)
- `just update`: bump `flake.lock`; `just gc`: delete generations older than 7 days
- `just check-hosts`: evaluate every machine; `just validate`: this one
- `just sysconfigs`, `just homeconfigs`, `just evalsysconfigs <attr>`: read the config without building

`nix develop` in the repo root gives you `just` and `shellcheck`. CI (`.github/workflows/check.yml`)
evaluates every host, builds the shared home layer, and runs shellcheck and the bootstrap tests
(`bash nix/scripts/tests/bootstrap.test.sh`).

#### Imperative package installs

- Use nix profile to imperatively install packages instead through home-manager config



## Homebrew (nix-darwin only)

Homebrew covers what nix does poorly on macOS: GUI applications and Mac App Store
apps. CLI tooling still belongs in home-manager — see section 8 of `LEARN.md` for
the full decision order.

Managed by `modules.homebrew` in `nix/nix-darwin/modules/homebrew/default.nix`.

### One-time setup

nix-darwin manages Homebrew's *contents*, but does not install Homebrew itself.
Bootstrap it once (`./bootstrap.sh vgmacbook --with-homebrew` does the same before the first build):

```bash
just brew-bootstrap
```

That installs Homebrew if missing, then adopts any declared cask whose app is
already installed by hand (see *Migrating* below). It is idempotent - safe to
re-run. Then `just build`.

Until Homebrew exists, activation prints a red
`error: Homebrew is not installed, skipping...` and carries on harmlessly.

Related recipes:

| Recipe | Does |
|---|---|
| `just brew-bootstrap` | Install Homebrew, then adopt already-installed casks |
| `just brew-adopt` | Adoption pass on its own, without reinstalling anything |
| `just brew-check` | Report drift read-only, without changing anything |
| `just brewfile` | Print the declared Brewfile (works before any build) |

`brew-check` is worth an occasional run because `just build` cannot fix either
kind of drift it reports. `brew bundle` trusts Homebrew's receipts: a cask whose
app you deleted still has a receipt, so the rebuild skips it rather than putting
it back, and an app installed by hand has no receipt to skip on. Anything marked
`DRIFT` is fixed by `just brew-adopt`.

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

Then `just build`. Never `brew install` directly — see the guardrail below.

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

Do this once per already-installed app, before the first `just build` that
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
just evalhomeconfigs home.shellAliases
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
