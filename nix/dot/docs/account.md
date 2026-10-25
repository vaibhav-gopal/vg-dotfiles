# Your account

## Password

Your first login asks you to set one (`dot passwd` does it too). It's for unlocking things at the
machine; SSH stays key-only. Change it later with `passwd`.

## Git and GitHub

Your git identity is yours to set (it lands in `~/.gitconfig`):

```sh
git config --global user.name "Your Name"
git config --global user.email you@example.com
gh auth login        # GitHub over HTTPS, through the gh CLI
```

## Claude Code

`claude` is installed; the first run walks you through logging in with your own account.

## Your shell

zsh and bash are set up (prompt, completion, `z`/`cd` jumping, `fzf`, `eza` as `ls`). The managed
`~/.zshrc` and `~/.bashrc` are rewritten on every rebuild, so your own additions (aliases, PATH,
exports) go in `~/.zshrc.local` and `~/.bashrc.local`, which they source last.
