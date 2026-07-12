#!/usr/bin/env bash
# Runs on the HOST. Opens Claude Code inside a single, dedicated, always-available container
# named "cc". On first run it creates the container (node:bookworm-slim, ~200MB), installs
# Claude Code, and wires ~/.claude to the shared config in this repo via bootstrap.sh. On every
# later run it just reconnects and launches `claude` — no rebuild.
#
# Unlike `seed` (one container per project), `cc` is a single long-lived scratch box. Its working
# files live on the host in ~/cc-workspace (mounted at /workspace) and survive restarts, as does
# Claude's memory/history (~/cc-state).
#
# Usage:
#   cc [claude args...]   start (creating if needed) the cc container and launch `claude [args...]`
#   cc --rebuild [...]    remove and recreate the container from scratch, then launch
#
# Config repo location is derived from where this script lives (override with CLAUDE_DEV_ENV).
set -euo pipefail

NAME=cc
IMAGE=node:bookworm-slim

REBUILD=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --rebuild) REBUILD=1 ;;
    *)         ARGS+=("$arg") ;;
  esac
done

# Resolve this script's real location through any symlink chain (it's meant to be symlinked
# onto PATH, e.g. ~/.local/bin/cc), so the config-repo path is the clone, not the bin dir.
SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SELF="$(cd -P "$(dirname "$SOURCE")" && pwd)"
CLAUDE_DEV_ENV="${CLAUDE_DEV_ENV:-$SELF}"

WORKSPACE="$HOME/cc-workspace"
STATE="$HOME/cc-state"

# --- preconditions ---
command -v docker >/dev/null 2>&1 || { echo "error: docker not on PATH" >&2; exit 1; }
[[ -d "$CLAUDE_DEV_ENV" && -f "$CLAUDE_DEV_ENV/bootstrap.sh" ]] || {
  echo "error: config repo not found at CLAUDE_DEV_ENV=$CLAUDE_DEV_ENV" >&2
  echo "       this must be a real host path — it gets bind-mounted into the container." >&2
  exit 1
}
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" && ! -f "$HOME/.claude/.credentials.json" ]]; then
  echo "warning: no CLAUDE_CODE_OAUTH_TOKEN set and no ~/.claude/.credentials.json — claude may" >&2
  echo "         prompt to log in. Mint one once: export CLAUDE_CODE_OAUTH_TOKEN=\"\$(claude setup-token)\"" >&2
fi

# --- mount targets must pre-exist on the host (a file bind mount needs an existing source) ---
mkdir -p "$WORKSPACE" "$STATE/projects"
[[ -f "$STATE/claude.json" ]] || printf '{}\n' > "$STATE/claude.json"

exists()  { [[ -n "$(docker ps -aq --filter "name=^/${NAME}$")" ]]; }
running() { [[ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" == "true" ]]; }

if [[ "$REBUILD" -eq 1 ]] && exists; then
  echo "cc: removing existing container for rebuild…"
  docker rm -f "$NAME" >/dev/null
fi

if ! exists; then
  echo "cc: creating '$NAME' container ($IMAGE)…"

  # SSH agent forwarding for git (optional). macOS+OrbStack exposes the host agent at a fixed
  # path; on Linux use the host's $SSH_AUTH_SOCK.
  ssh_mount=()
  if [[ "$(uname -s)" == "Darwin" ]]; then
    ssh_mount=(-v /run/host-services/ssh-auth.sock:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent)
  elif [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
    ssh_mount=(-v "$SSH_AUTH_SOCK":/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent)
  fi

  # Auth: pass the OAuth token through if set; else mount a credentials file if the host has one.
  creds_mount=()
  [[ -f "$HOME/.claude/.credentials.json" ]] && \
    creds_mount=(-v "$HOME/.claude/.credentials.json":/home/node/.claude/.credentials.json)

  docker run -d --name "$NAME" \
    -e CLAUDE_CODE_OAUTH_TOKEN \
    -v "$CLAUDE_DEV_ENV":/home/node/claude-dev-env \
    -v "$CLAUDE_DEV_ENV/general/skills":/home/node/.claude/skills \
    -v "$STATE/projects":/home/node/.claude/projects \
    -v "$STATE/claude.json":/home/node/.claude.json \
    -v "$WORKSPACE":/workspace \
    ${ssh_mount[@]+"${ssh_mount[@]}"} ${creds_mount[@]+"${creds_mount[@]}"} \
    -w /workspace \
    "$IMAGE" sleep infinity >/dev/null

  # The .claude/.claude.json mounts get auto-created owned by root; reclaim them for the node user
  # so bootstrap and claude can write (matches the templates' postCreate chown).
  docker exec -u root "$NAME" chown node:node /home/node/.claude /home/node/.claude.json /workspace

  # node:*-slim ships without git/curl/ca-certificates — claude's installer and git need them.
  echo "cc: installing packages + Claude Code…"
  docker exec -u root "$NAME" bash -c \
    'apt-get update -qq && apt-get install -y -qq --no-install-recommends git curl ca-certificates >/dev/null && rm -rf /var/lib/apt/lists/*'

  # Install Claude Code, then wire ~/.claude to the mounted config repo (general layer only —
  # no framework, this is a general-purpose container). Skills aren't wired here — general/skills
  # is bind-mounted straight onto ~/.claude/skills above.
  docker exec -u node "$NAME" bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
  docker exec -u node "$NAME" bash /home/node/claude-dev-env/bootstrap.sh
elif ! running; then
  docker start "$NAME" >/dev/null
fi

# --- open claude inside (login shell so the installer's PATH addition is picked up) ---
exec docker exec -it -u node -w /workspace "$NAME" \
  bash -lc 'export PATH="$HOME/.local/bin:$PATH"; exec claude "$@"' -- ${ARGS[@]+"${ARGS[@]}"}
