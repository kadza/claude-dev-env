#!/usr/bin/env bash
# Runs on the HOST. Scaffolds a new project from a template, starts its devcontainer,
# and drops you into a shell inside where Claude Code is configured.
# Usage: seed.sh <tech> <name> [--project-config <path>] [--project-config-target <rel-path>]
#
# Config repo location: derived from where this script lives and exported so the templates'
# ${localEnv:CLAUDE_DEV_ENV} mount resolves. Always run rebuilds through seed (it re-exports the
# path) so you never have to set CLAUDE_DEV_ENV by hand. Advanced override: set CLAUDE_DEV_ENV to
# mount a config repo other than the one seed.sh lives in.
#
# --project-config <path>: symlinks this project's .claude/ + CLAUDE.md wholesale to an external,
# unversioned directory you manage yourself (a separate git repo you've already cloned), replacing
# whatever the template put there. The path is bind-mounted into the container at the same absolute
# path via PROJECT_CONFIG_DIR, always exported below (pointing at a fixed empty placeholder when
# this flag is omitted) since the templates mount it unconditionally. See docs/adr/0030-0035.
#
# --project-config-target <rel-path>: place the symlinks at <rel-path>/.claude + <rel-path>/CLAUDE.md
# instead of the project root — for a repo that nests the real project in a subdirectory (e.g. a
# monorepo's api/). Relative to the project root; requires --project-config. See docs/adr/0036.
set -euo pipefail

PROJECT_CONFIG=""
PROJECT_CONFIG_TARGET=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-config)
      PROJECT_CONFIG="${2:-}"
      [[ -n "$PROJECT_CONFIG" ]] || { echo "error: --project-config requires a path" >&2; exit 1; }
      shift 2 ;;
    --project-config-target)
      PROJECT_CONFIG_TARGET="${2:-}"
      [[ -n "$PROJECT_CONFIG_TARGET" ]] || { echo "error: --project-config-target requires a path" >&2; exit 1; }
      shift 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL[@]}"

TECH="${1:-}"
NAME="${2:-}"
if [[ -z "$TECH" || -z "$NAME" ]]; then
  echo "usage: seed <tech> <name> [--project-config <path>] [--project-config-target <rel-path>]" >&2
  exit 1
fi
if [[ -n "$PROJECT_CONFIG_TARGET" ]]; then
  [[ -n "$PROJECT_CONFIG" ]] || { echo "error: --project-config-target requires --project-config" >&2; exit 1; }
  case "$PROJECT_CONFIG_TARGET" in
    /*) echo "error: --project-config-target must be relative to the project root, not absolute: $PROJECT_CONFIG_TARGET" >&2; exit 1 ;;
    *..*) echo "error: --project-config-target must not contain '..': $PROJECT_CONFIG_TARGET" >&2; exit 1 ;;
  esac
fi

# Resolve this script's real location through any symlink chain (seed is meant to be symlinked
# onto PATH, e.g. ~/.local/bin/seed), so the config-repo path is the clone, not the bin dir.
SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SELF="$(cd -P "$(dirname "$SOURCE")" && pwd)"
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
if [[ -n "$PROJECT_CONFIG" ]]; then
  [[ -d "$PROJECT_CONFIG" ]] || { echo "error: --project-config path not found: $PROJECT_CONFIG" >&2; exit 1; }
  PROJECT_CONFIG="$(cd "$PROJECT_CONFIG" && pwd)"
fi

# Project config mount source (docs/adr/0033): always exported, pointing at --project-config when
# given or a fixed empty placeholder otherwise — the templates mount PROJECT_CONFIG_DIR
# unconditionally, and a bind mount's source must always exist.
PROJECT_CONFIG_EMPTY="$HOME/.claude-project-config-empty"
mkdir -p "$PROJECT_CONFIG_EMPTY"
export PROJECT_CONFIG_DIR="${PROJECT_CONFIG:-$PROJECT_CONFIG_EMPTY}"

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

# Project config (docs/adr/0030): replace .claude/ + CLAUDE.md wholesale with symlinks into the
# external directory, so edits made from inside the container write back there automatically.
# Lands at the project root unless --project-config-target says otherwise (docs/adr/0036).
if [[ -n "$PROJECT_CONFIG" ]]; then
  TARGET_DIR="$PROJECT"
  [[ -z "$PROJECT_CONFIG_TARGET" ]] || TARGET_DIR="$PROJECT/$PROJECT_CONFIG_TARGET"
  mkdir -p "$TARGET_DIR"
  rm -rf "$TARGET_DIR/.claude" "$TARGET_DIR/CLAUDE.md"
  ln -s "$PROJECT_CONFIG/.claude" "$TARGET_DIR/.claude"
  ln -s "$PROJECT_CONFIG/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
  echo "seed: linked .claude/ + CLAUDE.md to project config at $PROJECT_CONFIG (in ${PROJECT_CONFIG_TARGET:-project root})"
fi

# Persisted Claude state (§9). Mount targets must pre-exist; idempotent.
#   projects/    → ~/.claude/projects  (session transcripts, memory)
#   claude.json  → ~/.claude.json      (theme/onboarding/trust/history)
# Just guarantee the file exists so the bind mount resolves; bootstrap.sh (in-container) injects
# the UI defaults (dark mode + onboarding) from general/claude.json on every run.
mkdir -p "$STATE/projects"
[[ -f "$STATE/claude.json" ]] || printf '{}\n' > "$STATE/claude.json"

# Shared screenshot inbox (global, not per-project): macOS screenshots saved to ~/claude-shots on the
# host appear in every container at ~/.claude-shots. Mount source must pre-exist; idempotent.
mkdir -p "$HOME/claude-shots"

# --- up + in ---
devcontainer up --workspace-folder "$PROJECT"
exec devcontainer exec --workspace-folder "$PROJECT" bash
