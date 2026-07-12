# claude-dev-env

A seed tool. `d seed <tech> <name>` scaffolds a new project, starts its devcontainer, and drops you into
a shell where Claude Code is fully configured from this repo. `d clone <tech> <url> [name]` does the same
for a repo that already exists on GitHub — cloning it and injecting the env glue. See
[`decisions.md`](decisions.md) for the full design and rationale.

**One command to rule them.** `d` is the umbrella that dispatches to everything below — it's the only
project command you install (plus `cc`, the standalone scratch box):

```sh
d seed   node-ts my-experiment       # scaffold a new project + container
d clone  node-ts git@github.com:owner/repo.git   # from an existing GitHub repo
d up     kite-lodz                   # start an existing project's container + drop into it
d unseed kite-lodz                   # tear a project down
d cc     "fix this bug"              # = cc "fix this bug"
d help                               # list commands
```

`d <cmd>` just runs `<cmd>.sh` from this repo, exporting `CLAUDE_DEV_ENV` first. Only `d` and `cc` are
put on your PATH; `seed`/`clone`/`up`/`unseed` are reached through `d`.

**Live write-back.** This repo is bind-mounted into every container and `~/.claude` is wired to it with
symlinks, so config is shared, not copied. Editing a skill or rule (or approving a permission) inside a
container writes straight back to your host clone — visible to every other container on this machine
instantly, no git needed. To share beyond this machine, `git commit && git push` from the host clone;
other machines pick it up on `git pull`. (Editing an existing skill is live; adding a *new* one needs
`bootstrap.sh <tech>` re-run in already-running containers.)

## One-time host setup (macOS + OrbStack)

1. **Clone this repo** anywhere on the host:
   ```sh
   git clone <this-repo> ~/claude-dev-env
   ```
   Step 5's `setup.sh` links the commands and exports `CLAUDE_DEV_ENV` into your shell profile from
   here — nothing else to configure by hand.
2. **devcontainer CLI** on PATH:
   ```sh
   npm install -g @devcontainers/cli
   ```
3. **ssh-agent** running with your git key loaded (`ssh-add -l` should list it). OrbStack forwards the
   host agent into containers at `/run/host-services/ssh-auth.sock` (already wired in the templates).
4. **Claude auth token** — on macOS credentials live in the Keychain, not a file, so mint a token once
   and export it (add to your shell profile):
   ```sh
   export CLAUDE_CODE_OAUTH_TOKEN="$(claude setup-token)"
   ```
   The templates pass this into the container so `claude` starts authenticated with no login prompt.
   *(On Linux you can instead mount `~/.claude/.credentials.json` — see the commented mount in each
   template's `devcontainer.json`.)*
5. **Run `setup.sh`** — links the commands and wires your shell profile in one shot:
   ```sh
   ~/claude-dev-env/setup.sh                 # bin dir ~/.local/bin, profile ~/.zshrc
   ~/claude-dev-env/setup.sh /usr/local/bin  # different bin dir (must already exist + be on PATH)
   PROFILE=~/.bashrc ~/claude-dev-env/setup.sh   # different shell profile
   ```
   It (a) symlinks the two standalone commands, `d` and `cc`, into the bin dir, and (b) writes a managed
   block to your profile:
   ```sh
   # >>> claude-dev-env >>>
   export CLAUDE_DEV_ENV="/Users/you/claude-dev-env"
   export PATH="$HOME/.local/bin:$PATH"      # only if that dir isn't already on PATH
   # <<< claude-dev-env <<<
   ```
   Idempotent — re-run anytime; the block is rewritten in place (never duplicated) and links refreshed.
   Open a new shell (or `source` the profile) afterward.

   **Why the `CLAUDE_DEV_ENV` export matters:** the commands set it themselves, but any container you
   bring up *without* them — a bare `devcontainer up`, `devcontainer exec`, or `devpod ssh` from a fresh
   terminal — reads `${localEnv:CLAUDE_DEV_ENV}` from that shell. If it's unset the config-repo mount
   source is empty and Docker fails with `invalid mount config … field Source must not be empty`. Having
   it in your profile makes every shell resolve the mount.

## Usage

```sh
d seed node-ts my-experiment    # or: d seed python my-experiment
```

This creates `~/projects/my-experiment`, `~/claude-state/my-experiment`, does a first commit, brings the
devcontainer up, and execs a shell inside. `claude` is ready with the general + framework rules and the
`grill-me` skill.

Re-running `d seed <tech> <name>` on an **existing** project skips scaffolding and rebuilds/reconnects its
container. To just get back in without a rebuild, use `d up <name>` (below).

The seeded container is named after the project (via `${localWorkspaceFolderBasename}`), so it shows up
as `<name>` in OrbStack / `docker ps`.

### Reconnecting to an existing project

```sh
d up kite-lodz     # a bare name → ~/projects/kite-lodz
d up .             # the current directory (cd into the project first); d up alone means the same
d up ~/work/repo   # any path also works, even outside ~/projects
```

Use this from any fresh terminal to get back into a project whose container is stopped (or was never
started this session). It's a thin wrapper over `devcontainer up` + `devcontainer exec … bash` that
first exports `CLAUDE_DEV_ENV`, so the config-repo mount resolves even from a bare shell — the exact
failure you'd otherwise hit with a raw `devcontainer up` or `devpod ssh` when the variable isn't in your
profile (`invalid mount config … field Source must not be empty`). The argument is a project **name**
(mapped to `~/projects/<name>`) or a **path** (`.`, `..`, or any dir with a slash) used as the workspace
folder directly; omitting it means `.`. State is keyed off the folder basename, so `d up .` from
`~/projects/kite-lodz` reuses the same Claude memory as `d up kite-lodz`. `d up` never scaffolds or
clones; it errors if the folder (or its `.devcontainer/`) is missing. `devcontainer up` is idempotent,
so it's safe whether the container is stopped, missing, or already running.

> Reconnect with the **same** CLI you created the project with (`devcontainer`). `devcontainer` and
> `devpod` each build their own container from the same `devcontainer.json`; mixing them makes one
> rebuild from scratch instead of attaching.

### From an existing GitHub repo

```sh
d clone node-ts git@github.com:owner/repo.git    # or an https:// URL
d clone python https://github.com/owner/repo my-name   # optional 3rd arg overrides the name
```

Where `seed` scaffolds a fresh project, `clone` takes a repo that already lives on GitHub. It derives the
project name from the URL (`…/owner/repo.git` → `repo`; pass a 3rd arg to override), `git clone`s the repo
into `~/projects/<name>` (keeping its own `.git`, history, and remote), then injects the tech template's
`.devcontainer/` and `.claude/` so the container comes up wired to this config. From there it's identical
to `seed` — state dir, `devcontainer up`, shell.

The injected files are **left uncommitted** in the working tree (they show as untracked/modified in
`git status`), so they never risk being pushed upstream — `clone` makes no commit. The `.devcontainer/`
is replaced wholesale so our `devcontainer.json` (config-repo mount + `bootstrap.sh <tech>`) is the one
used; a repo's own `.devcontainer/` is overwritten. Re-running `clone` on an existing project resumes
(rebuild/reconnect) and skips the clone + inject, just like `seed`. Use `git pull` inside to update the
code. Teardown is the same `d unseed <name>`.

### Teardown

```sh
d unseed <name>                 # remove the container, ~/projects/<name>, and ~/claude-state/<name>
d unseed -y <name>              # skip the confirmation prompt
d unseed --keep-state <name>    # remove container + project, but keep Claude memory/history
```

Destructive (deletes the project git repo and, unless `--keep-state`, its Claude memory), so it confirms
first. Containers are matched by devcontainer label and by name, so it also cleans up projects seeded
before the naming change.

## `cc` — a single dedicated Claude Code container

Where `seed` gives you **one container per project**, `cc` gives you **one shared, always-available**
container for quick work — a personal Claude Code sandbox that isn't tied to any project.

```sh
cc                    # start (creating on first run) the 'cc' container and launch claude
cc "fix this bug"     # any args are passed through to claude
cc --rebuild          # tear down and recreate the container from scratch, then launch
```

First run creates a container named `cc` on `node:bookworm-slim` (~200MB — much smaller than the
devcontainer node images `seed` uses), installs Claude Code, and wires `~/.claude` to this repo via
`bootstrap.sh` with **no framework layer** (general rules + skills only). Every later run just
reconnects and launches `claude` — no rebuild. It reuses the same auth (`CLAUDE_CODE_OAUTH_TOKEN` or a
mounted credentials file), SSH-agent, and config-repo mounts as the templates, so config edits on the
host are live inside `cc` too.

Unlike seeded projects, `cc` is a general scratch box, so its files and Claude state live in fixed
host dirs that survive restarts (and `--rebuild`):

- `~/cc-workspace/` → `/workspace` (the working directory) — put files here to keep them.
- `~/cc-state/` → Claude memory/history/onboarding (`projects/` and `claude.json`).

Teardown is just Docker (no `unseed` needed): `docker rm -f cc` (state and workspace on the host are
kept). Use `cc --rebuild` if you only want to refresh the container itself — e.g. after your auth token
changes, since the token is captured at container-create time.

## How config reaches the container

`~/claude-dev-env` is bind-mounted into every container. Its `bootstrap.sh <tech>` (run by
`postCreateCommand`) writes a 2-line `~/.claude/CLAUDE.md` that `@import`s `general/CLAUDE.md` +
`frameworks/<tech>/CLAUDE.md`, symlinks `general/settings.json` to `~/.claude/settings.json`, and symlinks
each skill dir into `~/.claude/skills/`. Because these point at the mount, edits on the host take effect
live, and in-session approvals/skill edits write **back** into this repo — commit them and every future
project inherits them.

Per-project Claude state lives on the host at `~/claude-state/<name>/` and survives container rebuilds:
`projects/` (session transcripts/memory) mounts to `~/.claude/projects`, and `claude.json` mounts to
`~/.claude.json` (theme/onboarding/trust/history) so rebuilds skip onboarding and remember trusted folders.

UI defaults come from [`general/claude.json`](general/claude.json)
(`{"theme":"dark","hasCompletedOnboarding":true}` — dark mode, onboarding pre-completed). Every run of
`bootstrap.sh` merges these into `~/.claude.json`, filling only **missing** keys — so Claude's own state
(`userID`, history, per-project trust) is preserved and a theme you pick yourself is never overridden.
Because it runs on every bootstrap, it's self-healing: re-run `bootstrap.sh <tech>` in any container to
apply new defaults, no re-seed needed. Edit `general/claude.json` to change the defaults. Note: theme
lives here, in `~/.claude.json` — **not** in `settings.json` (which has no `theme` key).

Auth is separate and file-less: `claude` reads `CLAUDE_CODE_OAUTH_TOKEN` from the environment at startup
(see host setup step 4), so there is intentionally **no** `~/.claude/.credentials.json` inside the
container — that's expected, not a failure.

## Existing projects

For a repo on GitHub, `clone <tech> <url>` (above) automates the whole path — clone, inject env glue,
bring the container up. The manual equivalent, for a project you already have checked out: inside its
devcontainer, bind-mount + clone this repo and run once:
```sh
~/claude-dev-env/bootstrap.sh <tech>
```
The user-level `~/.claude` stub then covers the general + framework layers with zero footprint in the
project repo. Keep project-specific rules in that project's own config.
