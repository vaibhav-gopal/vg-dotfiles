# Running work on this machine with Slurm

Slurm schedules this machine's cores, memory and Tenstorrent card between everyone who uses it. Anything
bigger than editing files or a quick compile runs as a **job**: you ask for what you need, Slurm starts
it when that's free, and nobody steps on anyone else.

## What there is

| | |
|---|---|
| Partition | `main` (the only one; the default) |
| CPUs | 24 (12 cores × 2 threads); Slurm hands out whole cores, so `-c 1` gets 2 |
| Memory | about 48 GiB for jobs; a job that doesn't say gets 2 GiB per CPU |
| Card | one Blackhole p150a, as `--gres=tt:1`; only a job that holds it can open `/dev/tenstorrent/0` |
| Time | 1 hour unless you ask (`-t`), at most 2 days |
| Your login shell | everyone's shells share 2 CPUs and 8 GiB, so don't build or run big things there |

Who goes first when jobs wait: fairshare. The less you've used lately, the higher your next job's
priority (`sprio`, `sshare` show it).

## Try something now: an interactive job

```sh
srun -c 8 --mem=16G --pty bash                 # a shell with 8 CPUs, no card
srun --gres=tt:1 -c 8 --mem=16G --pty bash     # the same, holding the card
srun --gres=tt:1 -c 8 --mem=16G -t 4:00:00 --pty bash   # for 4 hours
```

Exit the shell and the job ends, and the card is free for the next person. Inside it, `tt-smi` shows the card.

## Run something unattended: a batch job

Put the work in a script with its request at the top:

```sh
#!/usr/bin/env bash
#SBATCH --job-name=matmul-sweep
#SBATCH --gres=tt:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=6:00:00
#SBATCH --output=logs/%x-%j.out     # %x = job name, %j = job id
set -euo pipefail

cd ~/projects/my-experiment
nix develop --command python run.py --size 4096
```

```sh
mkdir -p logs && sbatch job.sh    # prints the job id
squeue -u $USER                   # yours, waiting (PD) or running (R)
tail -f logs/matmul-sweep-<id>.out
scancel <id>                      # stop it
```

The job starts in the directory you ran `sbatch` from, with your environment as it was then.

## Experiments: many runs at once

A **job array** runs the same script over a list of inputs. Each task gets its own `$SLURM_ARRAY_TASK_ID`:

```sh
#SBATCH --array=0-9          # ten tasks; --array=0-9%2 runs at most two at a time
sizes=(512 1024 2048 4096 8192 16384 32768 512 1024 2048)
python run.py --size "${sizes[$SLURM_ARRAY_TASK_ID]}" > "results/run-$SLURM_ARRAY_TASK_ID.json"
```

There is one card, so array tasks that ask for `--gres=tt:1` run one after another; CPU-only tasks
(no `--gres`) run side by side, as many as the cores and memory allow.

**Chains:** `sbatch --dependency=afterok:<id> analyse.sh` starts only once job `<id>` has finished
cleanly, e.g. a CPU job that gathers the results of a card job.

## Where files go

- **Your home directory** (`~`) is yours alone and stays: keep code, inputs and results there.
- **`/tmp` and `/dev/shm` inside a job** are the job's own and are **wiped when it ends**. Use them for
  scratch, and copy anything you need out before the script finishes.
- **Hugepages** (`/dev/hugepages-1G`): the card's host runtime maps them; whatever your job leaves
  there is cleared when your last job ends.

## Tools and environments

Nothing is installed system-wide for you beyond the basics, and you can't use sudo. Bring your own:

- **For a project:** a `flake.nix` with a dev shell, then `nix develop` (in a job:
  `nix develop --command <cmd>`). `dot help devshells` shows how to start one.
- **For a one-off:** `nix shell nixpkgs#<package>` (e.g. `nix shell nixpkgs#python3 nixpkgs#uv`).
- **Python:** `uv venv && uv pip install ...` inside your project folder. Prebuilt wheels and Linux
  binaries work (nix-ld is on).

Build inside a job when it's heavy (`srun -c 16 --mem=32G make -j16`), not in your login shell.

## Seeing what's going on

| | |
|---|---|
| `sinfo` | is the machine idle, mixed (partly busy) or allocated (full)? |
| `scontrol show node` | `AllocTRES` includes `gres/tt=1` while someone holds the card |
| `squeue -u $USER` | your jobs; you see only your own, not other people's |
| `squeue -j <id> --start` | when Slurm expects a waiting job to start |
| `sacct -j <id> -o JobID,State,Elapsed,MaxRSS,ExitCode` | how a finished job went, and how much memory it really used |
| `sstat -j <id>` | live usage of a running job |

## Good habits

- Ask for what you use. Too much memory or time makes your job wait longer and holds up everyone else.
  `sacct ... MaxRSS` after a first run tells you the real figure.
- Release the card: exit interactive shells you've finished with, and don't leave `--gres=tt:1` jobs
  sitting idle. When a job ends, Slurm takes the card back and stops anything still holding it.
- Set `-t` near what you need: short jobs fit into gaps between others (backfill) and start sooner.
- Put each experiment's request in its script (`#SBATCH`), so it's repeatable and in git with the code.
