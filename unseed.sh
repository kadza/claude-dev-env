#!/usr/bin/env bash
# Runs on the HOST. Tears down a seeded project: its devcontainer, project dir, and Claude state.
# Usage: unseed.sh [-y|--yes] [--keep-state] <name>
#   -y / --yes     skip the confirmation prompt
#   --keep-state   preserve ~/claude-state/<name> (Claude memory/history/trust)
set -euo pipefail

FORCE=0
KEEP_STATE=0
NAME=""
for arg in "$@"; do
  case "$arg" in
    -y|--yes)      FORCE=1 ;;
    --keep-state)  KEEP_STATE=1 ;;
    -*)            echo "unknown option: $arg" >&2; exit 1 ;;
    *)             NAME="$arg" ;;
  esac
done

if [[ -z "$NAME" ]]; then
  echo "usage: unseed [-y] [--keep-state] <name>" >&2
  exit 1
fi

PROJECT="$HOME/projects/$NAME"
STATE="$HOME/claude-state/$NAME"

command -v docker >/dev/null 2>&1 || { echo "error: docker not on PATH" >&2; exit 1; }

# Find container(s): by devcontainer label (robust to any naming scheme) and by the explicit
# --name we now set. Dedupe.
ids="$(docker ps -aq --filter "label=devcontainer.local_folder=$PROJECT" 2>/dev/null || true)"
named="$(docker ps -aq --filter "name=^/${NAME}$" 2>/dev/null || true)"
ids="$(printf '%s\n%s\n' "$ids" "$named" | sort -u | sed '/^$/d')"

echo "About to remove for '$NAME':"
echo "  container(s): $({ [[ -n "$ids" ]] && echo "$ids" | tr '\n' ' '; } || echo '<none found>')"
echo "  project dir : $PROJECT$([[ -d "$PROJECT" ]] || echo '  (missing)')"
if [[ "$KEEP_STATE" -eq 1 ]]; then
  echo "  state dir   : KEPT ($STATE)"
else
  echo "  state dir   : $STATE$([[ -d "$STATE" ]] || echo '  (missing)')"
fi

if [[ "$FORCE" -ne 1 ]]; then
  read -rp "Delete these permanently? [y/N] " ans
  [[ "$ans" == [yY] ]] || { echo "aborted."; exit 0; }
fi

[[ -n "$ids" ]] && docker rm -f $ids >/dev/null
rm -rf "$PROJECT"
[[ "$KEEP_STATE" -eq 1 ]] || rm -rf "$STATE"
echo "unseed: removed '$NAME'."
