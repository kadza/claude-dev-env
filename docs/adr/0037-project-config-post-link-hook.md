# Project config can supply an optional `post-link.sh` hook

After `seed.sh`/`clone.sh` (re)create the `.claude/` symlink for `--project-config`, they check for an
executable `post-link.sh` at the project config's root and, if present, run it with `"$PROJECT"
"$TARGET_DIR"`. This exists for repo-specific follow-up that `claude-dev-env` has no business knowing
about — e.g. a cloned repo that already tracks `.claude/settings.json` (or `CLAUDE.md`) upstream needs
`git update-index --skip-worktree` on those paths plus a `.git/info/exclude` entry for the symlink
itself, or `git status` reports the tracked file as deleted and the symlink as untracked. That's a
convention of the *target repo's* `.gitignore`, not something every `--project-config` user has, so the
logic belongs in the user-owned project config directory (docs/adr/0032), not in this repo. Rejected:
hardcoding the skip-worktree/exclude dance into `seed.sh`/`clone.sh` directly — would fix the common case
but forces it on every project config regardless of whether the target repo actually tracks anything
under `.claude/`, and keeps git-convention-specific logic in a repo that's supposed to stay tech/convention
agnostic.
