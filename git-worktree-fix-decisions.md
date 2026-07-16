# Git worktrees not visible from the host — design decisions

Standalone design doc for applying the git-worktree host-visibility fix to `claude-dev-env`'s
devcontainer templates. Written in the style of the repo's `decisions.md`; not yet merged into it.

## Problem

Claude Code (running inside a devcontainer) creates git worktrees under `.claude/worktrees/<name>/`
inside the repo. From the host, `cd`-ing to the equivalent host-side folder and running `git status`
errors out, and `git worktree list` (or any host git command touching the worktree) reports it as
broken/removed. The worktree's files are real and intact (it's a live bind mount, nothing is missing)
— this is a path-translation problem, not data loss.

**Root cause.** `git worktree` linkage is two small files holding **absolute paths**
(`<main-repo>/.git/worktrees/<name>/gitdir` and `<worktree>/.git`). Both are written by git running
inside the container, so both hardcode the container's mount path (`/workspaces/<repo-name>`).
Standard devcontainer behavior mounts the host repo clone into the container at
`/workspaces/<folder-name>` — a different absolute path than wherever the repo actually lives on the
host. Same underlying files, different path string depending on which side (host vs. container) is
looking at them, so git resolves the stored absolute paths against whichever filesystem view is
running the command and breaks from the other side. `git worktree repair` only rewrites paths to match
whichever environment you run it from — it can't make one worktree resolve correctly from two different
absolute path prefixes simultaneously. This fix was already validated in another repo (`kite-lodz`)
before being applied here.

---

## §1 — Scope: which devcontainer.json files get the fix

**Decision.** Edit `templates/node-ts/.devcontainer/devcontainer.json` and
`templates/python/.devcontainer/devcontainer.json` only. Do not edit the root
`.devcontainer/devcontainer.json` directly.

**Reasoning.** `diff` confirmed the root config is byte-identical to `templates/node-ts`'s — this repo
dev-containers itself off its own node-ts template, it isn't a distinct self-hosting case. `up.sh
--rebuild .` run from the repo root matches by `image` field to `templates/node-ts` and copies that
template's `.devcontainer/` over the root one, then recreates the container. So fixing the two templates
and rebuilding covers all three cases (root + both templates) through the one existing mechanism —
editing root directly would just be overwritten by the next `--rebuild` anyway, and would drift from the
template in the meantime.

**Alternatives rejected.**
- *Edit root + both templates* — redundant given the byte-identical relationship; three edits to keep
  in sync instead of two.

---

## §2 — Testing now vs. deferring

**Decision.** Edit the template files only in this session. Do not run `d up --rebuild .` to test.

**Reasoning.** Rebuilding recreates the container this session is running in
(`--remove-existing-container`), which would drop the current session. The user chose to control when
that happens rather than have it triggered automatically as part of this change.

**How to test later:** from the host, `d up --rebuild <name>` (or `d up --rebuild .` from inside a
project directory), then confirm `git worktree list` resolves consistently from both host and container
for any existing worktrees. Pre-existing worktrees (created before the rebuild) will still have stale
absolute paths baked into their `.git` linkage files — run `git worktree repair` once per such worktree
from whichever side you want it usable from next.

---

## §3 — Already-seeded projects

**Decision.** Out of scope for this session. Templates get the fix now; existing projects pick it up
individually via `d up --rebuild <name>` (the existing mechanism — see `up.sh`'s doc comment) whenever
the user gets to each one.

**Reasoning.** `~/projects/*` lives on the host, outside what's visible from inside this container —
there's no way to enumerate or touch them from here. Per-project rebuild is already the established
path for picking up template changes (mounts, `runArgs`, image, `containerEnv`), so no new tooling is
needed.

---

## §4 — README documentation

**Decision.** Add a new "## Git worktrees" section to `README.md`, placed after "## Existing projects"
(before "## Screenshots into the container"). Explain why the templates mount at the host's absolute
path and flag the portability caveat (Docker Desktop for Mac without OrbStack, or WSL with
path-translation quirks, may not tolerate mounting at an arbitrary host-style absolute path as the
container target).

**Reasoning.** The repo's README gives standalone sections to notable mount-related behavior
("Screenshots into the container" is the precedent) rather than folding everything into the host-setup
list. Worktree visibility is its own discoverable topic, not an OrbStack-specific setup step, so a
dedicated section fits the existing structure better than appending to "## One-time host setup".

**Alternatives rejected.**
- *Fold into "## One-time host setup (macOS + OrbStack)"* — that section is about one-time host
  prerequisites (devcontainer CLI, ssh-agent, auth token); this fix is a template behavior change, not a
  setup step, so it reads oddly bundled there.

---

## §5 — Mount syntax

**Decision.** Add, in both templates:
```json
"workspaceMount": "source=${localWorkspaceFolder},target=${localWorkspaceFolder},type=bind,consistency=cached",
"workspaceFolder": "${localWorkspaceFolder}",
```

**Reasoning.** Directly reuses the syntax already validated in the `kite-lodz` fix — `consistency=cached`
is a no-op outside Docker Desktop for Mac (OrbStack/Linux ignore it) and costs nothing to include for
portability. `${localWorkspaceFolder}` resolves to the host's actual absolute path to the repo, and using
it as both source and target means the container sees the repo at that same path, so any absolute paths
git (or anything else) writes resolve identically from both host and container. Already confirmed no
hardcoded `/workspaces/<repo-name>` references exist anywhere in this repo (root, templates, or
`bootstrap.sh`) that this change would break.
