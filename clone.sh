#!/usr/bin/env bash
# Runs on the HOST. Clones an existing GitHub repo into a project, injects the Claude env glue
# (the tech template's .devcontainer/ + .claude/), starts its devcontainer, and drops you into a
# shell inside where Claude Code is configured. The counterpart to seed.sh for repos that already
# exist on GitHub — see docs/adr/0012 through 0018 for the clone-command decisions.
# Usage: clone.sh <tech> <url> [name] [--project-config <path>] [--project-config-target <rel-path>]
#
# Config repo location: derived from where this script lives and exported so the templates'
# ${localEnv:CLAUDE_DEV_ENV} mount resolves — identical to seed.sh.
#
# --project-config <path>: see seed.sh's header and docs/adr/0030 through 0035 — symlinks this
# project's .claude/ + CLAUDE.md wholesale to an external, unversioned directory you manage
# yourself, replacing whatever was injected from the template.
#
# --project-config-target <rel-path>: place the symlinks in a subdirectory instead of the project
# root — see seed.sh's header and docs/adr/0036 (e.g. a monorepo that nests the real project, like
# this repo's own backend under api/, so the config needs to live there instead).
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
URL="${2:-}"
NAME_OVERRIDE="${3:-}"
if [[ -z "$TECH" || -z "$URL" ]]; then
  echo "usage: clone <tech> <url> [name] [--project-config <path>] [--project-config-target <rel-path>]" >&2
  exit 1
fi
if [[ -n "$PROJECT_CONFIG_TARGET" ]]; then
  [[ -n "$PROJECT_CONFIG" ]] || { echo "error: --project-config-target requires --project-config" >&2; exit 1; }
  case "$PROJECT_CONFIG_TARGET" in
    /*) echo "error: --project-config-target must be relative to the project root, not absolute: $PROJECT_CONFIG_TARGET" >&2; exit 1 ;;
    *..*) echo "error: --project-config-target must not contain '..': $PROJECT_CONFIG_TARGET" >&2; exit 1 ;;
  esac
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
if [[ -n "$PROJECT_CONFIG" ]]; then
  [[ -d "$PROJECT_CONFIG" ]] || { echo "error: --project-config path not found: $PROJECT_CONFIG" >&2; exit 1; }
  PROJECT_CONFIG="$(cd "$PROJECT_CONFIG" && pwd)"
fi

# Project config mount source (docs/adr/0033): always exported — see seed.sh for the full rationale.
PROJECT_CONFIG_EMPTY="$HOME/.claude-project-config-empty"
mkdir -p "$PROJECT_CONFIG_EMPTY"
export PROJECT_CONFIG_DIR="${PROJECT_CONFIG:-$PROJECT_CONFIG_EMPTY}"

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
  #   .nvim.lua      — host-side Neovim LSP/formatter glue for this tech, when the template ships
  #                    one (e.g. python, node-ts). Replaced wholesale, same as .devcontainer/.
  rm -rf "$PROJECT/.devcontainer"
  cp -R "$TEMPLATE/.devcontainer" "$PROJECT/"
  mkdir -p "$PROJECT/.claude"
  cp -R "$TEMPLATE/.claude/." "$PROJECT/.claude/"
  INJECTED=".devcontainer/ + .claude/"
  if [[ -f "$TEMPLATE/.nvim.lua" ]]; then
    cp "$TEMPLATE/.nvim.lua" "$PROJECT/.nvim.lua"
    INJECTED="$INJECTED + .nvim.lua"
  fi
  echo "clone: injected $INJECTED from '$TECH' template (uncommitted, left in the working tree)."
fi

# Project config (docs/adr/0030, 0036): replace .claude/ + CLAUDE.md wholesale with symlinks —
# see seed.sh. Lands at the project root unless --project-config-target says otherwise.
if [[ -n "$PROJECT_CONFIG" ]]; then
  TARGET_DIR="$PROJECT"
  [[ -z "$PROJECT_CONFIG_TARGET" ]] || TARGET_DIR="$PROJECT/$PROJECT_CONFIG_TARGET"
  mkdir -p "$TARGET_DIR"
  rm -rf "$TARGET_DIR/.claude" "$TARGET_DIR/CLAUDE.md"
  ln -s "$PROJECT_CONFIG/.claude" "$TARGET_DIR/.claude"
  ln -s "$PROJECT_CONFIG/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
  echo "clone: linked .claude/ + CLAUDE.md to project config at $PROJECT_CONFIG (in ${PROJECT_CONFIG_TARGET:-project root})"
fi

# Persisted Claude state (§9). Mount targets must pre-exist; idempotent. Identical to seed.sh.
mkdir -p "$STATE/projects"
[[ -f "$STATE/claude.json" ]] || printf '{}\n' > "$STATE/claude.json"

# Shared screenshot inbox (global, not per-project): macOS screenshots saved to ~/claude-shots on the
# host appear in every container at ~/.claude-shots. Mount source must pre-exist; idempotent.
mkdir -p "$HOME/claude-shots"

# --- up + in ---
devcontainer up --workspace-folder "$PROJECT"
exec devcontainer exec --workspace-folder "$PROJECT" bash
