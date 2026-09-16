# claude-dev-env

Seed tool and shared config repo for spinning up devcontainer-based Claude Code environments (see root `CLAUDE.md` for the full architecture).

## Language

**Layer**:
One of the three built-in tiers (`general/`, `frameworks/<tech>/`, `templates/<tech>/`) composed inside `~/.claude` by `bootstrap.sh`. Owned and versioned inside claude-dev-env itself.

**Project config**:
An external, unversioned directory — a separate git repo the user clones and manages independently — symlinked into a single project's `.claude/` and `CLAUDE.md` at the project root via the `--project-config` flag. Not owned or versioned by claude-dev-env, and not one of the three layers.
_Avoid_: Layer (it isn't one — it's external and per-project, not part of claude-dev-env's own composition), companion config, external config
