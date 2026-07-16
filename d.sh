#!/usr/bin/env bash
# Runs on the HOST. Unified entry point for the Claude dev-env commands. `d <command> [args…]`
# dispatches to the sibling <command>.sh in this repo, so the tool stays a thin, self-extending
# umbrella: drop a new foo.sh next to this file and `d foo` works with no edit here.
#
#   d seed   <tech> <name>                 scaffold a new project + container, drop into it
#   d clone  <tech> <url> [name]           clone a GitHub repo into a project + container, drop in
#   d up     [--rebuild] [<name>|.]         start an existing project's container + drop in (. = cwd)
#   d unseed [-y] [--keep-state] <name>    tear a project down (container + dirs)
#   d cc     [claude args…]                open Claude in the shared scratch container
#   d help                                 show this list
#
# CLAUDE_DEV_ENV is resolved from this script's location and exported here, so every dispatched
# command (and the devcontainer mounts it triggers) sees it without you setting it by hand.
set -euo pipefail

# Resolve this script's real location through any symlink chain (d is symlinked onto PATH, e.g.
# ~/.local/bin/d), so we find the sibling command scripts in the clone, not the bin dir.
SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SELF="$(cd -P "$(dirname "$SOURCE")" && pwd)"
export CLAUDE_DEV_ENV="${CLAUDE_DEV_ENV:-$SELF}"

usage() {
  sed -n '5,12p' "$SELF/d.sh" | sed 's/^# \{0,1\}//'
}

CMD="${1:-help}"
[[ $# -gt 0 ]] && shift

case "$CMD" in
  seed|clone|up|unseed|cc)
    [[ -f "$SELF/$CMD.sh" ]] || { echo "d: $SELF/$CMD.sh not found" >&2; exit 1; }
    exec "$SELF/$CMD.sh" "$@" ;;
  -h|--help|help)
    usage ;;
  *)
    echo "d: unknown command '$CMD'" >&2
    echo >&2
    usage >&2
    exit 1 ;;
esac
