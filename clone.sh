#!/usr/bin/env bash
# Runs on the HOST. Clones an existing GitHub repo into a project, injects the Claude env glue
# (the tech template's .devcontainer/ + .claude/), starts its devcontainer, and drops you into a
# shell inside where Claude Code is configured. The counterpart to seed.sh for repos that already
# exist on GitHub — see §12 in decisions.md.
# Usage: clone.sh <tech> <url> [name]
#
# Config repo location: derived from where this script lives and exported so the templates'
# ${localEnv:CLAUDE_DEV_ENV} mount resolves — identical to seed.sh.
set -euo pipefail

TECH="${1:-}"
URL="${2:-}"
NAME_OVERRIDE="${3:-}"
if [[ -z "$TECH" || -z "$URL" ]]; then
  echo "usage: clone <tech> <url> [name]" >&2
  exit 1
fi

# Resolve this script's real location through any symlink chain (clone is meant to be symlinked
# onto PATH, e.g. ~/.local/bin/clone), so the config-repo path is the clone, not the bin dir.
SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SELF="$(cd -P "$(dirname "$SOURCE")" && pwd)"
CLAUDE_DEV_ENV="${CLAUDE_DEV_ENV:-$SELF}"
export CLAUDE_DEV_ENV

# Name from the repo basename (strip trailing slash + .git), unless overridden by the 3rd arg.
#   git@github.com:owner/repo.git  → repo
#   https://github.com/owner/repo  → repo
NAME="$NAME_OVERRIDE"
if [[ -z "$NAME" ]]; then
  NAME="$(basename "${URL%/}")"
  NAME="${NAME%.git}"
fi
[[ -n "$NAME" ]] || { echo "error: could not derive a project name from '$URL' — pass one explicitly: clone $TECH $URL <name>" >&2; exit 1; }

TEMPLATE="$CLAUDE_DEV_ENV/templates/$TECH"
PROJECT="$HOME/projects/$NAME"
STATE="$HOME/claude-state/$NAME"

# --- preconditions (same set as seed.sh) ---
[[ -d "$CLAUDE_DEV_ENV" && -f "$CLAUDE_DEV_ENV/bootstrap.sh" ]] || {
  echo "error: config repo not found at CLAUDE_DEV_ENV=$CLAUDE_DEV_ENV" >&2
  echo "       clone claude-dev-env to that path, or set CLAUDE_DEV_ENV to where it lives." >&2
  echo "       this must be a real host path — it gets bind-mounted into every container." >&2
  exit 1
}
[[ -d "$TEMPLATE" ]] || { echo "error: no template for '$TECH' at $TEMPLATE" >&2; exit 1; }
command -v devcontainer >/dev/null 2>&1 || { echo "error: 'devcontainer' CLI not on PATH (npm i -g @devcontainers/cli)" >&2; exit 1; }
[[ -n "${SSH_AUTH_SOCK:-}" ]] || echo "warning: SSH_AUTH_SOCK unset — is ssh-agent running with your key loaded? git over SSH (clone + push) may fail." >&2

# --- clone (new project) or resume (existing) ---
if [[ -e "$PROJECT" ]]; then
  echo "clone: $PROJECT exists — resuming (rebuild/reconnect), skipping clone + inject."
else
  git clone "$URL" "$PROJECT"

  # Inject the env glue from the tech template, always overwriting, left UNCOMMITTED. The cloned
  # repo keeps its own .git/history/remote — we make no commit, so these files never risk being
  # pushed upstream (they show as untracked/modified in `git status`; that's expected).
  #   .devcontainer/ — replaced wholesale so OUR devcontainer.json (config-repo mount + the
  #                    `bootstrap.sh <tech>` call) is authoritative, not the repo's own if any.
  #   .claude/       — merged in (settings.local.json permission allowlist) without nuking any
  #                    other .claude/ content the repo may ship.
  rm -rf "$PROJECT/.devcontainer"
  cp -R "$TEMPLATE/.devcontainer" "$PROJECT/"
  mkdir -p "$PROJECT/.claude"
  cp -R "$TEMPLATE/.claude/." "$PROJECT/.claude/"
  echo "clone: injected .devcontainer/ + .claude/ from '$TECH' template (uncommitted, left in the working tree)."
fi

# Persisted Claude state (§9). Mount targets must pre-exist; idempotent. Identical to seed.sh.
mkdir -p "$STATE/projects"
[[ -f "$STATE/claude.json" ]] || printf '{}\n' > "$STATE/claude.json"

# --- up + in ---
devcontainer up --workspace-folder "$PROJECT"
exec devcontainer exec --workspace-folder "$PROJECT" bash
