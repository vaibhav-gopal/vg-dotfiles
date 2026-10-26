# Shared folders

Your home folder is yours alone. To keep files together with others on this machine, use a
**shared folder**: `/srv/shared/<name>`, open to its members only. `dot help shared` lists the
folders here and who's in each; `id -nG` shows the ones you're in (as `shared-<name>`).

What you **make** there (save from an editor, write from a program, `mkdir`) is writable by every
member, whatever your umask. What you **copy** in (`cp`, `rsync`, `mv` from your home) keeps the
original's permissions, often read-only for others, so open it up once it's there:

```sh
cd /srv/shared/everyone
cp -r ~/results/run-12 . && chmod -R g+rwX run-12   # copy in, then let the others change it
ln -s /srv/shared/everyone ~/everyone               # a shortcut from your home
```

## Just added to one?

A new membership shows up at your next login: log out and back in (or start a new `ssh`).
Already-running zellij sessions keep the old groups until you start a new one.

If you linger (`dot help background`), your user services and the containers you started with
`podman run -d` don't pick it up at login: they run under your user manager, which keeps going
across logins with the groups it started with. They get the new one at the next reboot, or sooner
if the admin restarts your user manager (`systemctl restart user@<your uid>`), which stops them all
first, so say when that's convenient.

## From a job or a container

Slurm jobs reach the folders like your shell does. A rootless container needs your groups passed
in, or it's refused:

```sh
podman run --rm --group-add keep-groups -v /srv/shared/everyone:/data docker.io/library/alpine ls /data
```

## A new folder, or someone added

Ask the admin: the folders and their members are part of the machine's configuration
(`profiles.shared`).
