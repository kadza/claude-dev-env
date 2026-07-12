# claude-dev-env — design decisions & implementation reference

Outcome of a design grilling session (2026-07-09). This document is self-contained: everything needed to
build `claude-dev-env` from an empty repo is here, including initial content for the config files
(appendices).

**The idea:** a seed tool. `seed <tech> <name>` scaffolds a new project for a picked tech (Node+TS and
Python first), spins up its devcontainer, and lands you in a shell where Claude Code is fully configured
from this repo, which is cloned once on the host and bind-mounted into every container.

---

## Part 1 — Decisions and rationale

### 1. What is the system for?

**Decision:** Greenfield-first. The tool creates a *seed* of a project; the shared Claude config is made
available inside its devcontainer. Existing projects are served by a lighter manual path (§11).

**Why:** The recurring pain is starting new experiments with a fully configured environment. All projects
run in devcontainers (no VS Code — devcontainer CLI); mix of solo and team repos; config must never be
committed into project repos.

### 2. Repo topology

**Decision:** This repo (`claude-dev-env`) holds the **general** and **framework** layers plus
`templates/`, `seed.sh`, `bootstrap.sh`. **Project-specific** config lives in a small dedicated repo per
project.

**Why:** Project layers are explicitly excluded from the shared repo — per-project repos keep ownership
clean and can be shared individually. Rejected: monorepo with `projects/` (mixes unrelated projects);
repo-per-framework (version skew, N clones per container, no benefit for a single user).

### 3. Persistence model: devcontainers

**Decision:** Standard devcontainers. `seed.sh` creates the project directory on the host; devcontainer
machinery bind-mounts it. No custom docker orchestration.

**Why:** Rejected: named volumes + push-to-git (unpushed work at risk, invisible from host); ephemeral
containers (easy to lose work).

### 4. The seed tool

**Decision:** A small CLI script in this repo: `seed <tech> <name>` → creates `~/projects/<name>` from
`templates/<tech>/`, `git init` + first commit, `devcontainer up`, exec a shell inside.

**Why:** Single-user tool, no publishing overhead. Rejected: devcontainer templates registry (publishing
machinery, still needs a wrapper); GitHub template repos (couples seeding to GitHub, scatters templates).

### 5. Config delivery into the container

**Decision:** Each template's `.devcontainer` runs a `postCreateCommand` that installs Claude Code and
executes `bootstrap.sh <tech>` from the mounted repo.

**Why:** Not on VS Code, so `dotfiles.repository` auto-clone is less natural; devcontainer features run at
build time before home/auth exist and need publishing. Trade-off accepted: existing/team projects run
bootstrap manually once.

### 6. Composing layers inside `~/.claude`

**Decisions:**
- **CLAUDE.md:** bootstrap generates a 2-line `~/.claude/CLAUDE.md` stub containing absolute `@import`s of
  `general/CLAUDE.md` and `frameworks/<tech>/CLAUDE.md`. Content stays versioned; stub is regenerable.
  Rejected: symlink + relative `@import` (resolution through symlinks is fragile); concatenation (edits to
  the repo don't take effect live).
- **Skills:** `general/skills/` is bind-mounted straight onto `~/.claude/skills/` by the devcontainer,
  so add/remove/edit are all live — no bootstrap involvement (a running `claude` just needs a restart to
  rescan). Rejected: per-skill symlinks created by bootstrap (a *new* skill needed a bootstrap re-run and
  *deletes* left dangling symlinks behind); copying (loses write-back). Framework-scoped skills were
  dropped — general skills apply everywhere, and per-framework needs can live in a project's own
  `.claude/skills/` if they ever arise.
- **Framework selection:** no detection logic — each template's postCreate calls `bootstrap.sh <tech>`;
  the template knows its own tech.

### 7. Host clone, bind-mounted (the write-back property)

**Decision:** One clone of this repo on the host (`~/claude-dev-env`); every template bind-mounts it;
bootstrap symlinks point at the mount.

**Why:** In-session changes (approved permissions, skill edits) write back to the repo instantly; one
`git pull` on the host updates all containers. Rejected: per-container clones (in-session config changes
die with the container unless pushed); docker-volume clone (invisible from host).

### 8. Credentials

**Decision:** SSH agent forwarding for git; the host's Claude credential file mounted into the container
home by the template.

**Why:** No secrets in images, no login dance per container. Host prerequisite: ssh-agent running with the
key loaded. Rejected: fresh `claude login` per container (friction); PAT/tokens in env (larger leak
surface).

### 9. Claude runtime state across rebuilds

**Decision:** Templates mount a host dir (`~/claude-state/<project>`) over the container's
`~/.claude/projects`, so memory/history/trust survive rebuilds and are inspectable from the host.

**Why:** Long-lived seeds accumulate valuable project memory. Rejected: named volumes (hidden, prunable);
ephemeral (memory lost every rebuild).

### 10. Permissions layering

**Decision:** Two files, no merge tooling:
- `~/.claude/settings.json` → symlink to `general/settings.json` (git commands, `Skill(*)`, universal tools).
- Each template ships a starter `.claude/settings.local.json` pre-filled with that tech's allowlist
  (npm/vitest for node-ts, uv/pytest for python). Gitignored by convention; natural target for in-session
  approvals.

**Why:** Settings are JSON (no `@import`) and Claude Code has only user + project slots — no framework
slot. This keeps live write-back on both files. Rejected: folding all frameworks' perms into general
(every container allows every tech's commands); jq-merging into a generated user settings file (approvals
land in a generated file, never reach the repo).

### 11. Existing projects

**Decision:** Existing projects keep their own per-project config repos for project-level config. Inside
an existing project's devcontainer, clone this repo and run `bootstrap.sh <tech>` once — the user-level
`~/.claude` stub covers the general and framework layers with zero footprint in the project repo.

**Why:** One home for general rules; every improvement made once. Rejected: leaving existing projects out
(general-rule improvements duplicated across configs).

---

## Part 2 — Implementation spec

### Target repo layout

```
claude-dev-env/
  general/
    CLAUDE.md            # Appendix A
    settings.json        # Appendix C
    skills/
      grill-me/          # Appendix D
  frameworks/
    node-ts/
      CLAUDE.md          # start minimal; grows with use
    python/
      CLAUDE.md
    react/
      CLAUDE.md          # Appendix B
  templates/
    node-ts/
      .devcontainer/devcontainer.json
      .claude/settings.local.json
      .gitignore         # includes .claude/settings.local.json
      package.json, tsconfig.json, src/index.ts, (vitest config)
    python/
      .devcontainer/devcontainer.json
      .claude/settings.local.json
      .gitignore
      pyproject.toml, src/, (pytest config)
  bootstrap.sh
  seed.sh
  decisions.md           # this file
```

### bootstrap.sh

Runs *inside* the container. Usage: `bootstrap.sh <tech>` where `<tech>` names a dir under `frameworks/`.

- Resolve `REPO` = directory the script lives in (the bind-mounted repo — do not hardcode the path).
- Generate `~/.claude/CLAUDE.md` (plain file, overwrite):
  ```
  @$REPO/general/CLAUDE.md
  @$REPO/frameworks/<tech>/CLAUDE.md
  ```
  (absolute paths as resolved in the container)
- `ln -sfn $REPO/general/settings.json ~/.claude/settings.json`
- Skills are *not* wired here — the devcontainer bind-mounts `general/skills/` straight onto
  `~/.claude/skills/`, so add/remove is live with no re-run.
- Must be idempotent — safe to re-run anytime.
- Fail loudly if `<tech>` missing or the frameworks dir doesn't exist.

### seed.sh

Runs on the *host*. Usage: `seed.sh <tech> <name>`.

1. Preconditions: `templates/<tech>` exists; `~/projects/<name>` doesn't; `devcontainer` CLI on PATH;
   warn if `SSH_AUTH_SOCK` unset.
2. `mkdir -p ~/projects/<name>` and copy `templates/<tech>/` contents into it.
3. `mkdir -p ~/claude-state/<name>` (state mount target must pre-exist).
4. `git init` + initial commit in the project.
5. `devcontainer up --workspace-folder ~/projects/<name>`
6. `devcontainer exec --workspace-folder ~/projects/<name> bash` (interactive shell; claude is ready).

Optionally symlink `seed` onto PATH (`ln -s ~/claude-dev-env/seed.sh ~/.local/bin/seed`).

### Template devcontainer.json (node-ts sketch)

Container user is `node` for the typescript-node image; the python image uses `vscode` — adjust home paths
per template.

```jsonc
{
  "name": "seed-node-ts",
  "image": "mcr.microsoft.com/devcontainers/typescript-node:22",
  "mounts": [
    // the config repo — single host clone, live write-back (§7)
    "source=${localEnv:HOME}/claude-dev-env,target=/home/node/claude-dev-env,type=bind",
    // claude runtime state per project (§9)
    "source=${localEnv:HOME}/claude-state/${localWorkspaceFolderBasename},target=/home/node/.claude/projects,type=bind",
    // claude credentials (§8)
    "source=${localEnv:HOME}/.claude/.credentials.json,target=/home/node/.claude/.credentials.json,type=bind",
    // ssh agent socket (§8)
    "source=${localEnv:SSH_AUTH_SOCK},target=/ssh-agent,type=bind"
  ],
  "containerEnv": { "SSH_AUTH_SOCK": "/ssh-agent" },
  "postCreateCommand": "curl -fsSL https://claude.ai/install.sh | bash && /home/node/claude-dev-env/bootstrap.sh node-ts"
}
```

Notes / known caveats to verify during implementation:
- **Mount ordering:** the state mount targets a subdir of `~/.claude` and bootstrap also writes into
  `~/.claude` — verify the credentials file mount doesn't get shadowed; if it does, mount creds to a
  neutral path and have bootstrap symlink it.
- **macOS hosts:** Docker Desktop exposes the agent at `/run/host-services/ssh-auth.sock` instead of
  `${localEnv:SSH_AUTH_SOCK}`; on Linux/OrbStack the sketch above works. If the host stores Claude creds
  in the macOS keychain rather than `~/.claude/.credentials.json`, use `claude setup-token` once and mount
  the resulting file.
- The `postCreateCommand` runs as the container user with home available — this is why delivery isn't a
  devcontainer feature (§5).

### Starter settings.local.json (node-ts)

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run *)",
      "Bash(npm test*)",
      "Bash(npx vitest*)",
      "Bash(npx tsc*)"
    ]
  }
}
```

Python equivalent: `uv run *`, `uv sync*`, `pytest*`, `ruff*`. Keep these lists short — approvals grow
them organically per project.

### Implementation order (with acceptance checks)

1. **Repo skeleton + initial content.** Create the layout above; fill `general/CLAUDE.md` (Appendix A),
   `frameworks/react/CLAUDE.md` (Appendix B), `general/settings.json` (Appendix C), `grill-me` skill
   (Appendix D). Check: files in place; nothing project-specific (component maps, design-token catalogs)
   in `general/` or `frameworks/` — that content belongs in per-project config repos.
2. **bootstrap.sh.** Check: run in any container/shell with a fake `~`, produces stub + symlinks; re-run
   is a no-op; unknown tech fails loudly.
3. **templates/node-ts.** Check: `devcontainer up` on a hand-copied template works; inside the container,
   `claude` starts, reads general+framework rules, sees grill-me skill, git push works via agent, no login
   prompt.
4. **seed.sh.** Check: `seed node-ts scratch` end-to-end from an empty host dir; container rebuild keeps
   memory/history (state mount) and picks up config edits made on the host without rebuild.
5. **templates/python.** Clone from the working node-ts template; adjust image, user paths, starter perms.
6. **Existing projects.** In each existing project's devcontainer, clone this repo and run
   `bootstrap.sh <tech>`; remove any general/framework rules duplicated in that project's own config so
   this repo is their single source.

---

## Appendix A — general/CLAUDE.md (initial content)

```markdown
## Working With Me

When the user provides file paths, component names, or context about the codebase, trust that information.
Do not re-search the codebase for schemas, files, or structures the user has already described. If a file
isn't found on the first attempt, ask the user for the correct path instead of repeated glob/grep attempts.

## General Rules

Stay within the requested scope. Do not make changes to files or functionality the user did not ask about.
If you think adjacent changes are needed, ask first.

Never add `Co-Authored-By` trailers to git commits.

## Code Rules

Do not modify autogenerated files directly. If a fix requires changing generated output, find the
generator/source that produces it and fix there instead.

## Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:

- "Add a component" → "Render it in-browser, verify it matches the design"
- "Fix the bug" → "Reproduce it visually, then confirm the fix removes it"
- "Refactor X" → "Ensure typecheck + lint pass before and after"

For multi-step tasks, state a brief plan:

    1. [Step] → verify: [check]
    2. [Step] → verify: [check]
    3. [Step] → verify: [check]

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant
clarification.
```

## Appendix B — frameworks/react/CLAUDE.md (initial content)

Framework-level only. Project-specific material — component/design-system maps, a project's CSS variable
catalog (specific `--color-*`/typography/z-index names) — belongs in that project's own config repo, not
here.

```markdown
## Component Usage

When editing UI components, always check which custom components exist in the project (e.g., `<Button>`)
and what props they accept before using them. Never use plain HTML elements when a project component
exists, and never pass props (like `className`) that the component doesn't support.

When modifying existing UI components, reuse existing sub-components (arrows, navigation, badges) rather
than creating new ones. Check what already exists in the component before adding duplicates.

## CSS Conventions

Use `rem` units for all sizing/spacing, never `px`. Never use `margin-top`. Always nest CSS selectors
inside their parent blocks — do not place them outside.

All spacing and sizing values must align to a 4px grid. Using 1rem = 16px as the base, valid increments
are multiples of 0.25rem (0.25, 0.5, 0.75, 1rem, etc.). Do not use arbitrary values like 0.3rem or 0.6rem.

Use flexbox for layout by default. Do not use CSS grid without explicit approval from the user.

Use CSS variables from the project's variables file instead of raw values: colors (never hardcode hex/rgb),
semantic tokens over raw color variables, typography, shadows, and z-index (never raw numbers).
```

## Appendix C — general/settings.json (initial content)

Project-relative permissions (project script paths, a project's settings.local.json Read/Edit/Write
entries) belong in project settings; this is the general set:

```json
{
  "permissions": {
    "allow": [
      "Bash(git diff*)",
      "Bash(git ls-files*)",
      "Bash(git status*)",
      "Bash(git log*)",
      "Bash(git show*)",
      "Bash(git checkout *)",
      "Bash(git pull *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git config *)",
      "Bash(git branch *)",
      "Bash(git stash *)",
      "Skill(*)"
    ]
  }
}
```

## Appendix D — general/skills/grill-me/SKILL.md (initial content)

```markdown
---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down
each branch of the design tree, resolving dependencies between decisions one-by-one. For each question,
provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

## After the interview

Once all decisions are resolved, offer to write a `decisions.md` in the project root capturing each
decision with its rationale. This document is valuable as an implementation reference during coding, and
for sharing context with the team. Structure each entry as: the question that needed answering, the
decision made, and the reasoning behind it (including alternatives considered and why they were rejected).
```

---

## §12 — The `clone` command: seeding from an existing GitHub repo

Outcome of a design grilling session (2026-07-10). Automates the manual "existing projects" path of §11
for repos that live on GitHub. `clone <tech> <url> [name]` clones the repo into `~/projects/<name>`,
injects the tech template's env glue, and then follows the exact same up/exec flow as `seed`. Implemented
in `clone.sh`.

### 12.1 How is clone-mode invoked?

**Decision:** A **separate command** (`clone`), not an overload of `seed`'s second arg or a flag.

**Why:** Clean separation — the two flows differ fundamentally (git clone of a real remote vs. `git init`
scaffold), so a distinct verb keeps each script simple and its behavior obvious. Rejected: overloading
`seed <tech> <arg>` with URL-vs-name detection (a heuristic that can misfire, and mixes two behaviors in
one script); an explicit `--clone` flag (more typing, still one overloaded command).

### 12.2 How is the project name derived?

**Decision:** Default to the **repo basename** (strip trailing `/` then `.git`:
`git@github.com:owner/repo.git` → `repo`), with an **optional 3rd arg** to override
(`clone <tech> <url> [name]`).

**Why:** Matches "take the name from GitHub" for the common case, while the override escapes the two
collision cases (two owners with the same repo name; a clash with an existing scaffold under
`~/projects/`). Rejected: `owner-repo` always (longer dir/container names, not how you'd refer to the
project); basename with a hard error on collision (the override arg is a lighter escape hatch).

### 12.3 How are injected env files kept out of the upstream repo?

**Decision:** Copy them into the working tree and **leave them untracked** — `clone` makes no commit.

**Why:** The clone carries a live upstream remote; making no commit is the simplest guarantee that env
files never get pushed. The cost is a dirty `git status` (untracked/modified paths), which is acceptable
and documented. Rejected: registering them in `.git/info/exclude` (cleaner `git status`, but more
machinery than the user wanted); a local-only branch (heavier, still pushable by mistake).

### 12.4 What if the cloned repo already ships its own `.devcontainer/`?

**Decision:** **Always overwrite**, no backup, no conflict check — replace `.devcontainer/` wholesale.

**Why:** Our mechanism depends on *our* `devcontainer.json` (the config-repo bind mount + the
`bootstrap.sh <tech>` call); a repo's own devcontainer lacks these, so the Claude env wouldn't come up.
Since nothing is committed (§12.3), overwriting is non-destructive to the repo's history — the original is
recoverable via git. Rejected: abort-with-message (safe but obstructs the common goal); overwrite with a
timestamped backup (needless once we're not committing); a side path + `devcontainer up --config` (more
moving parts).

### 12.5 What gets injected from the template?

**Decision:** Inject **`.devcontainer/` + `.claude/`** only. `.devcontainer/` is replaced wholesale;
`.claude/` contents are merged in (so a repo's other `.claude/` files survive, only
`settings.local.json` is written). No scaffold source, no template `.gitignore`.

**Why:** `.devcontainer/` is the env glue; `.claude/settings.local.json` is the per-tech permission
allowlist worth carrying over. The repo already has its own source and `.gitignore`. Rejected:
`.devcontainer/` only (loses the pre-approved permission allowlist); everything-except-source (the
template `.gitignore` would shadow the repo's own rules).

### 12.6 When `~/projects/<name>` already exists?

**Decision:** **Resume**, exactly like `seed` — skip clone + inject, go straight to `devcontainer up` +
exec.

**Why:** Consistent mental model with `seed`; re-running is how you reconnect after closing the shell. It
deliberately does not re-pull — updating the code is the user's `git pull` inside. Rejected: erroring out
(less convenient for the common reconnect case).

### 12.7 Command name and installation

**Decision:** Name it **`clone`** (`clone.sh` in the repo root), added to `install-commands.sh`'s explicit
symlink list and documented in the README alongside `seed`.

**Why:** Matches the `seed`/`unseed`/`cc` verb style. Rejected: `seed-clone` (self-documenting but longer)
and `graft` (distinctive but opaque); the mild collision with "git clone" is acceptable given the verb-style
consistency.

### 12.8 clone.sh spec

Runs on the *host*. Usage: `clone.sh <tech> <url> [name]`.

1. Resolve `CLAUDE_DEV_ENV` from the script's real location (same symlink-chain resolution as seed.sh) and
   export it for the templates' `${localEnv:CLAUDE_DEV_ENV}` mount.
2. Preconditions (same set as seed.sh): config repo present, `templates/<tech>` exists, `devcontainer` CLI
   on PATH, warn if `SSH_AUTH_SOCK` unset (clone + push both need the agent).
3. Name: 3rd arg if given, else `basename` of the URL with a trailing `/` and `.git` stripped; error if
   empty.
4. If `~/projects/<name>` exists → resume (skip clone + inject). Else: `git clone <url> ~/projects/<name>`,
   then `rm -rf` the project's `.devcontainer/` and copy the template's in, and merge the template's
   `.claude/` contents in. No commit.
5. `mkdir -p ~/claude-state/<name>/projects` and ensure `claude.json` exists (same as seed.sh).
6. `devcontainer up` + `exec … bash`.
