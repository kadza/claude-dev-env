# claude-dev-env

A seed tool. `seed <tech> <name>` scaffolds a new project, starts its devcontainer, and drops you into a
shell where Claude Code is fully configured from this repo. See [`decisions.md`](decisions.md) for the
full design and rationale.

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
   `seed` derives the repo path from its own location and exports it as `CLAUDE_DEV_ENV` for the
   templates' bind mount — nothing to configure. (Always run rebuilds through `seed` too, so the
   path is re-exported; you never need `CLAUDE_DEV_ENV` in your shell profile.)
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
5. **Put `seed` on PATH** (optional):
   ```sh
   ln -s ~/claude-dev-env/seed.sh ~/.local/bin/seed
   ```

## Usage

```sh
seed node-ts my-experiment    # or: seed python my-experiment
```

This creates `~/projects/my-experiment`, `~/claude-state/my-experiment`, does a first commit, brings the
devcontainer up, and execs a shell inside. `claude` is ready with the general + framework rules and the
`grill-me` skill.

Re-running `seed <tech> <name>` on an **existing** project skips scaffolding and just rebuilds/reconnects
its container. Use this instead of a bare `devcontainer up` so the config-repo path is re-exported.

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

Inside an existing project's devcontainer, bind-mount + clone this repo and run once:
```sh
~/claude-dev-env/bootstrap.sh <tech>
```
The user-level `~/.claude` stub then covers the general + framework layers with zero footprint in the
project repo. Keep project-specific rules in that project's own config.
