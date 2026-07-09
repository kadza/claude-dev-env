#!/usr/bin/env bash
# Runs on the HOST. Scaffolds a new project from a template, starts its devcontainer,
# and drops you into a shell inside where Claude Code is configured.
# Usage: seed.sh <tech> <name>
#
# Config repo location: derived from where this script lives and exported so the templates'
# ${localEnv:CLAUDE_DEV_ENV} mount resolves. Always run rebuilds through seed (it re-exports the
# path) so you never have to set CLAUDE_DEV_ENV by hand. Advanced override: set CLAUDE_DEV_ENV to
# mount a config repo other than the one seed.sh lives in.
set -euo pipefail

TECH="${1:-}"
NAME="${2:-}"
if [[ -z "$TECH" || -z "$NAME" ]]; then
  echo "usage: seed <tech> <name>" >&2
  exit 1
fi

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DEV_ENV="${CLAUDE_DEV_ENV:-$SELF}"
export CLAUDE_DEV_ENV

TEMPLATE="$CLAUDE_DEV_ENV/templates/$TECH"
PROJECT="$HOME/projects/$NAME"
STATE="$HOME/claude-state/$NAME"

# --- preconditions ---
[[ -d "$CLAUDE_DEV_ENV" && -f "$CLAUDE_DEV_ENV/bootstrap.sh" ]] || {
  echo "error: config repo not found at CLAUDE_DEV_ENV=$CLAUDE_DEV_ENV" >&2
  echo "       clone claude-dev-env to that path, or set CLAUDE_DEV_ENV to where it lives." >&2
  echo "       this must be a real host path — it gets bind-mounted into every container." >&2
  exit 1
}
[[ -d "$TEMPLATE" ]] || { echo "error: no template for '$TECH' at $TEMPLATE" >&2; exit 1; }
command -v devcontainer >/dev/null 2>&1 || { echo "error: 'devcontainer' CLI not on PATH (npm i -g @devcontainers/cli)" >&2; exit 1; }
[[ -n "${SSH_AUTH_SOCK:-}" ]] || echo "warning: SSH_AUTH_SOCK unset — is ssh-agent running with your key loaded? git over SSH in the container may fail." >&2

# --- scaffold (new project) or resume (existing) ---
if [[ -e "$PROJECT" ]]; then
  echo "seed: $PROJECT exists — resuming (rebuild/reconnect), skipping scaffold."
else
  mkdir -p "$PROJECT"
  cp -R "$TEMPLATE/." "$PROJECT/"        # includes .devcontainer, .claude, .gitignore
  git -C "$PROJECT" init -q
  git -C "$PROJECT" add -A
  git -C "$PROJECT" commit -qm "Seed $NAME from $TECH template"
fi
# Persisted Claude state (§9). Mount targets must pre-exist; idempotent.
#   projects/    → ~/.claude/projects  (session transcripts, memory)
#   claude.json  → ~/.claude.json      (theme/onboarding/trust/history)
# Just guarantee the file exists so the bind mount resolves; bootstrap.sh (in-container) injects
# the UI defaults (dark mode + onboarding) from general/claude.json on every run.
mkdir -p "$STATE/projects"
[[ -f "$STATE/claude.json" ]] || printf '{}\n' > "$STATE/claude.json"

# --- up + in ---
devcontainer up --workspace-folder "$PROJECT"
exec devcontainer exec --workspace-folder "$PROJECT" bash
