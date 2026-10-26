# Keeping things running after you log out

Your **user manager** (`systemctl --user`) runs your user services and your containers. Normally it
stops when your last session ends, and takes them with it. With **lingering** on, it starts when
the machine boots and keeps running whether you're logged in or not. The admin turns it on per user
(`profiles.users.<you>.linger`); check yours with `loginctl show-user $USER -p Linger`.

## A terminal session: zellij

Leave a long command running in a zellij session and come back to it later:

```sh
zellij attach --create work     # start (or rejoin) the session named "work"
# run things; detach with F3 then d, or just close the terminal
zellij list-sessions            # later, from a new login
zellij attach work
```

## A service of your own

A program that should always be running (a small web app, a notebook server, a sync job) is a user
service: a file in `~/.config/systemd/user/`, here `~/.config/systemd/user/notebook.service`:

```ini
[Unit]
Description=My notebook server

[Service]
ExecStart=%h/projects/nb/.venv/bin/jupyter lab --no-browser --port 8888
WorkingDirectory=%h/projects/nb
Restart=on-failure

[Install]
WantedBy=default.target
```

```sh
systemctl --user daemon-reload
systemctl --user enable --now notebook      # start it now, and at every boot (with lingering)
systemctl --user status notebook
journalctl --user -u notebook -f            # its output
systemctl --user disable --now notebook     # stop it for good
```

`%h` is your home directory. A service starts with a bare environment, not your shell's: give
programs by their full path, as above.

## Containers

A container started with `podman run -d` keeps running after you log out while you linger. To have
it start again after a reboot, either give it a restart policy and turn on podman's restarter once:

```sh
podman run -d --restart=always --name db docker.io/library/postgres:16 ...
systemctl --user enable podman-restart      # once: starts every --restart=always container at boot
```

or describe it as a file (a quadlet), which makes it a user service like the one above:
`~/.config/containers/systemd/db.container`

```ini
[Container]
Image=docker.io/library/postgres:16
Environment=POSTGRES_PASSWORD=dev
PublishPort=5432:5432

[Install]
WantedBy=default.target
```

then `systemctl --user daemon-reload && systemctl --user start db`. (`dot help containers` for podman.)

## Long computations

Everything above shares the login sessions' slice of the machine (CPU and memory are capped
for all logins together on a shared server). Heavy work, and anything that needs the Tenstorrent
card, belongs in a Slurm job (`sbatch`), which gets its own cores and memory and runs whether you
linger or not: `dot help slurm`.
