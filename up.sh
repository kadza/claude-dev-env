#!/usr/bin/env bash
# Runs on the HOST. Starts (creating/starting as needed) an existing seeded or cloned project's
# devcontainer and drops you into a shell inside it. The reconnect counterpart to seed/clone: use
# it from a fresh terminal to get back into a project without re-scaffolding or re-cloning.
#
# Why this exists (not just `devcontainer up`): the templates mount the config repo via
# ${localEnv:CLAUDE_DEV_ENV}. That variable must be exported in the shell that launches the
# container, or the mount source resolves empty and Docker fails with
#   invalid mount config for type "bind": field Source must not be empty.
# seed/clone export it automatically; `up` does the same so a bare reconnect just works.
#
# Usage: up.sh [<name>|<path>]
#   up kite-lodz     reconnect to ~/projects/kite-lodz (a bare name → ~/projects/<name>)
#   up .             reconnect to the current directory (any path works, not just ~/projects)
#   up               same as `up .`
# The state dir is keyed off the project folder's basename, matching the template's
# ${localWorkspaceFolderBasename} mount — so `up .` from ~/projects/kite-lodz uses the same state.
set -euo pipefail

ARG="${1:-.}"

# Resolve this script's real location through any symlink chain (up is meant to be symlinked
# onto PATH, e.g. via `d`), so the config-repo path is the clone, not the bin dir.
SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SELF="$(cd -P "$(dirname "$SOURCE")" && pwd)"
CLAUDE_DEV_ENV="${CLAUDE_DEV_ENV:-$SELF}"
export CLAUDE_DEV_ENV

# Resolve the project folder. A path-like argument (., .., absolute, or anything with a slash) is
# taken as the workspace folder itself — so `up .` works from a project that doesn't live under
# ~/projects. A bare name maps to ~/projects/<name>, the seed/clone convention. PROJECT is made
# absolute so devcontainer's ${localWorkspaceFolderBasename} is stable regardless of how it's typed.
case "$ARG" in
  . | .. | /* | ./* | ../* | */*)
    PROJECT="$(cd "$ARG" 2>/dev/null && pwd)" || { echo "error: no such directory: $ARG" >&2; exit 1; } ;;
  *)
    PROJECT="$HOME/projects/$ARG" ;;
esac
NAME="$(basename "$PROJECT")"
STATE="$HOME/claude-state/$NAME"

# --- preconditions (same set as seed.sh) ---
[[ -d "$CLAUDE_DEV_ENV" && -f "$CLAUDE_DEV_ENV/bootstrap.sh" ]] || {
  echo "error: config repo not found at CLAUDE_DEV_ENV=$CLAUDE_DEV_ENV" >&2
  echo "       clone claude-dev-env to that path, or set CLAUDE_DEV_ENV to where it lives." >&2
  echo "       this must be a real host path — it gets bind-mounted into every container." >&2
  exit 1
}
[[ -d "$PROJECT" ]] || { echo "error: no project at $PROJECT — seed or clone it first" >&2; exit 1; }
[[ -f "$PROJECT/.devcontainer/devcontainer.json" ]] || { echo "error: no .devcontainer/ in $PROJECT — is this a seeded/cloned project?" >&2; exit 1; }
command -v devcontainer >/dev/null 2>&1 || { echo "error: 'devcontainer' CLI not on PATH (npm i -g @devcontainers/cli)" >&2; exit 1; }
[[ -n "${SSH_AUTH_SOCK:-}" ]] || echo "warning: SSH_AUTH_SOCK unset — is ssh-agent running with your key loaded? git over SSH in the container may fail." >&2

# Persisted Claude state (§9). Mount targets must pre-exist; idempotent. Identical to seed.sh —
# guard against a state dir that was pruned while the project stuck around.
mkdir -p "$STATE/projects"
[[ -f "$STATE/claude.json" ]] || printf '{}\n' > "$STATE/claude.json"

# --- up + in ---
devcontainer up --workspace-folder "$PROJECT"
exec devcontainer exec --workspace-folder "$PROJECT" bash
