# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`claude-dev-env` is not an application — it's a **seed tool** and shared config repo for spinning up
devcontainer-based Claude Code environments. One host clone of this repo is bind-mounted into every
container it creates, so config changes (and in-session permission approvals, skill/command edits) write
back live to this repo instead of being copied per-project. See [`decisions.md`](decisions.md) for the full
design rationale (written as a Q&A grilling transcript) and [`README.md`](README.md) for user-facing usage.

There is no build/lint/test step for this repo itself — the "code" is shell scripts and config files
consumed by the `devcontainer` CLI and Claude Code. Verifying a change means running the relevant script
(or a template's `devcontainer up`) and observing the result, not `npm test`.

## Commands (`d.sh` dispatch)

`d` is the single umbrella entrypoint; it dispatches `d <cmd> [args…]` to `<cmd>.sh` in this repo root
(dropping a new `foo.sh` here makes `d foo` work automatically — see `d.sh`). Only `d` and `cc` are
symlinked onto PATH by `setup.sh`; everything else is reached through `d`.

```sh
d seed   <tech> <name>                # scaffold a new project from templates/<tech>/, bring up + exec in
d clone  <tech> <url> [name]          # git clone an existing GitHub repo + inject template's env glue
d up     [--rebuild] [<name>|<path>]  # reconnect to an existing project's container (. = cwd)
d unseed [-y] [--keep-state] <name>   # tear down a project's container + host dirs
d cc     [claude args…]               # open Claude in the single shared scratch container
```

Each script is self-documented with an extensive header comment — read the script before modifying it,
since the comment explains *why*, not just what. `setup.sh` is the one-time host installer (symlinks `d`
and `cc`, writes the `CLAUDE_DEV_ENV` export block to the shell profile); it is not reached through `d`.

## Architecture: three layers composed inside `~/.claude`

1. **`general/`** — rules, skills, commands, and settings that apply to every project regardless of tech.
2. **`frameworks/<tech>/CLAUDE.md`** — one file per tech (`node-ts`, `python`, `react`), layered on top of
   general. No detection logic: each template's `postCreateCommand` calls `bootstrap.sh <tech>` explicitly,
   so the template is what selects the framework.
3. **`templates/<tech>/`** — the actual project scaffold (`.devcontainer/devcontainer.json`,
   `.claude/settings.local.json` pre-filled with that tech's command allowlist, source skeleton).

`bootstrap.sh` runs *inside* the container (via `postCreateCommand`) and wires these together:
- Writes a 2-line `~/.claude/CLAUDE.md` stub with absolute `@import`s of `general/CLAUDE.md` and
  `frameworks/<tech>/CLAUDE.md` (skipped if no tech, e.g. the `cc` container) — content stays versioned in
  this repo, the stub is just regenerated, never hand-edited.
- Symlinks `~/.claude/settings.json` → `general/settings.json` (so approvals write back to the repo).
- Merges `general/claude.json` UI defaults (theme, onboarding) into `~/.claude.json`, filling only missing
  keys — self-healing on every bootstrap run, never clobbers Claude's own state or a manually-picked theme.
- Does **not** wire skills/commands — `general/skills/` and `general/commands/` are bind-mounted directly
  onto `~/.claude/skills/` and `~/.claude/commands/` by the devcontainer `mounts` entry, so add/remove/edit
  is live with no bootstrap re-run (a running `claude` just needs a restart to rescan).
- Is idempotent; safe to re-run any time (e.g. `bash ~/claude-dev-env/bootstrap.sh node-ts` inside a
  container to pick up new defaults without a full rebuild).

Editing `general/CLAUDE.md`, a skill, or a command here changes behavior for every container immediately
(host and already-running containers alike, via the bind mount) — there's no per-project copy to keep in
sync unless the project has its own `.claude/` overrides.

## Two project lifecycles

- **`seed`** (`seed.sh`): scaffolds a brand-new project by copying `templates/<tech>/` into
  `~/projects/<name>`, `git init` + first commit, then `devcontainer up` + exec a shell in.
- **`clone`** (`clone.sh`): for a repo that already exists on GitHub. Clones it (keeping its own
  `.git`/history/remote), then injects the template's `.devcontainer/` (overwritten wholesale) and
  `.claude/` (merged, doesn't clobber other files) — **left uncommitted** so injected files never risk
  being pushed upstream. Everything after that is identical to `seed`.

Both are resumable: re-running with an existing project name skips scaffold/clone and just reconnects
(`devcontainer up` + exec), matching `d up`'s behavior. `d up --rebuild` (or `cc --rebuild`) is the only
path that re-syncs a project's stale `.devcontainer/` from its matching template (matched by `image`) and
forces container recreation — needed because `devcontainer.json` values (mounts, `runArgs`, image,
`containerEnv`) are baked at container-create time and a plain reconnect never picks up template changes.

## State that survives rebuilds

Per-project host directories, mounted into the container so Claude's memory and the git worktree resolve
consistently:
- `~/projects/<name>` — the project's own git working tree, mounted at the **same absolute path** inside
  the container (not remapped to `/workspaces/<name>`), specifically so `git worktree` linkage files (e.g.
  `.claude/worktrees/<name>/`, created by Claude Code) don't break when viewed from the other side.
- `~/claude-state/<name>/projects` → `~/.claude/projects` (session transcripts/memory).
- `~/claude-state/<name>/claude.json` → `~/.claude.json` (theme/onboarding/trust/history).
- `~/claude-shots` (global, not per-project) → `~/.claude-shots`, the screenshot inbox; read the newest
  file by mtime and delete it after use (see the `screenshot` skill/command and `general/CLAUDE.md`).

`cc` (the single shared scratch container, `cc.sh`) is the odd one out: general-layer-only (no framework),
`node:bookworm-slim` instead of a devcontainer image, fixed host dirs (`~/cc-workspace`, `~/cc-state`)
instead of per-project ones, and reconnect-only after first creation (no rebuild unless `--rebuild` is
passed explicitly).

## Making changes here

- Framework/general rule changes go in `general/CLAUDE.md` or `frameworks/<tech>/CLAUDE.md` — never
  project-specific detail (component maps, design tokens); that belongs in a project's own config.
- New skills/commands go under `general/skills/` / `general/commands/` — no wiring needed, just add the
  directory/file (see existing skills there for the SKILL.md frontmatter shape: `name`, `description`, and
  optionally `disable-model-invocation: true` for skills that shouldn't auto-trigger).
- Template changes (`templates/<tech>/.devcontainer/devcontainer.json`, starter
  `.claude/settings.local.json`) only reach existing projects via `d up --rebuild`, not existing running
  containers — mention this when the change is behavioral.
- Auth is deliberately file-less on macOS: `CLAUDE_CODE_OAUTH_TOKEN` is passed via `containerEnv`, not a
  mounted credentials file. Don't "fix" a missing `~/.claude/.credentials.json` inside a container — that's
  expected on macOS hosts.
