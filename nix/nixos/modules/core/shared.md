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

## From a job or a container

Slurm jobs reach the folders like your shell does. A rootless container needs your groups passed
in, or it's refused:

```sh
podman run --rm --group-add keep-groups -v /srv/shared/everyone:/data docker.io/library/alpine ls /data
```

## A new folder, or someone added

Ask the admin: the folders and their members are part of the machine's configuration
(`profiles.shared`).
