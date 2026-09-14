#!/usr/bin/env bash
# Runs on the HOST. Execs `claude` directly inside an already-running project container, in the
# exact shape an external tool ("Herdr") expects when it spawns/attaches to Claude Code agents:
#
#   HERDR_AGENT=claude docker exec -it -u <user> -w <workspace> <container> <path-to-claude> [args…]
#
# This bypasses the `devcontainer exec` wrapper that up.sh/cc.sh use — Herdr drives raw `docker
# exec` itself, so this script must produce that same invocation rather than something equivalent.
# HERDR_AGENT=claude is set on the docker-exec command's own environment (not passed into the
# container) so Herdr can identify/track the process it spawned.
#
# The container user and claude binary path differ per template (node-ts: user "node", python:
# user "vscode" — matching mcr.microsoft.com/devcontainers' base-image default remoteUser, which
# isn't written explicitly into either devcontainer.json). Rather than hardcode a tech→user map,
# the user is read off the project's own .devcontainer/devcontainer.json mounts, which all target
# /home/<user>/... — see templates/*/.devcontainer/devcontainer.json.
#
# Likewise the workspace dir: plain `docker exec` has no notion of devcontainer.json's
# workspaceFolder (that's a devcontainer-CLI concept), so without -w you land in the container's
# default WORKDIR (often /). We read workspaceFolder ourselves: templates/*.devcontainer.json set
# it to "${localWorkspaceFolder}" (same absolute path as the host project dir, since workspaceMount
# targets that same variable) — this repo's own .devcontainer/devcontainer.json doesn't override
# workspaceFolder at all, so it falls back to the devcontainer CLI's own default of
# /workspaces/<basename>.
#
# Usage: claude.sh [<name>|<path>] [claude args…]
#   claude.sh kite-lodz            exec claude in ~/projects/kite-lodz's container
#   claude.sh .                    exec claude in the current directory's container
#   claude.sh                      same as `claude.sh .`
#   claude.sh kite-lodz -p "hi"    extra args are passed straight through to claude
# Resolution matches up.sh: a bare name maps to ~/projects/<name>; anything path-like (., .., an
# absolute path, or containing a slash) is used as the project dir directly. The container must
# already be running — this script only execs into it (start it first with `d up <name>`).
set -euo pipefail

ARG=""
if [[ $# -gt 0 ]]; then
  case "$1" in
    . | .. | /* | ./* | ../* | */*) ARG="$1"; shift ;;
    -*) ARG="" ;;
    *)  ARG="$1"; shift ;;
  esac
fi
ARG="${ARG:-.}"

case "$ARG" in
  . | .. | /* | ./* | ../* | */*)
    PROJECT="$(cd "$ARG" 2>/dev/null && pwd)" || { echo "error: no such directory: $ARG" >&2; exit 1; } ;;
  *)
    PROJECT="$HOME/projects/$ARG" ;;
esac
NAME="$(basename "$PROJECT")"
DEVCONTAINER_JSON="$PROJECT/.devcontainer/devcontainer.json"

command -v docker >/dev/null 2>&1 || { echo "error: docker not on PATH" >&2; exit 1; }
[[ -d "$PROJECT" ]] || { echo "error: no project at $PROJECT — seed or clone it first" >&2; exit 1; }
[[ -f "$DEVCONTAINER_JSON" ]] || { echo "error: no .devcontainer/ in $PROJECT — is this a seeded/cloned project?" >&2; exit 1; }

running() { [[ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" == "true" ]]; }
running || { echo "error: container '$NAME' is not running — start it first with 'd up $ARG'" >&2; exit 1; }

# Every mount in these devcontainer.json files targets /home/<user>/..., so the remote user can be
# read off any one of them without a per-tech lookup table.
AGENT_USER="$(grep -oE '/home/[A-Za-z0-9_-]+/' "$DEVCONTAINER_JSON" | head -1 | sed -E 's#/home/([A-Za-z0-9_-]+)/#\1#')"
[[ -n "$AGENT_USER" ]] || { echo "error: couldn't determine the container user from $DEVCONTAINER_JSON" >&2; exit 1; }

CLAUDE_PATH="/home/$AGENT_USER/.local/bin/claude"

# workspaceFolder: "${localWorkspaceFolder}" literally means "same path as the host project dir"
# (see comment above); a hardcoded literal is used as-is; absent entirely falls back to
# devcontainer CLI's own default of /workspaces/<basename>.
WS_FIELD="$(grep -oE '"workspaceFolder"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEVCONTAINER_JSON" | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/' || true)"
if [[ -z "$WS_FIELD" ]]; then
  WORKSPACE="/workspaces/$NAME"
elif [[ "$WS_FIELD" == '${localWorkspaceFolder}' ]]; then
  WORKSPACE="$PROJECT"
else
  WORKSPACE="$WS_FIELD"
fi

HERDR_AGENT=claude exec docker exec -it -u "$AGENT_USER" -w "$WORKSPACE" "$NAME" "$CLAUDE_PATH" "$@"
