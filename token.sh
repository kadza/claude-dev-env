#!/usr/bin/env bash
# Runs on the HOST. Mints a CLAUDE_CODE_OAUTH_TOKEN by running `claude setup-token` inside the
# cc container (where claude is installed). Complete the browser/OAuth prompt.
# Run `d cc` first if the cc container doesn't exist yet.
#
# Usage:
#   d token                  run the auth flow and print the token
#   d token --write <token>  save token to ~/.claude-token  e.g. d token --write "sk-ant-..."
#   d token --write          run the auth flow, prompt to paste, save to ~/.claude-token
set -euo pipefail

WRITE=0
TOKEN=""
for arg in "$@"; do
  case "$arg" in
    --write) WRITE=1 ;;
    -*) echo "token: unknown option '$arg'" >&2; exit 1 ;;
    *)  TOKEN="$arg" ;;
  esac
done

save_token() {
  printf 'export CLAUDE_CODE_OAUTH_TOKEN="%s"\n' "$1" > "$HOME/.claude-token"
  echo "saved to ~/.claude-token" >&2
  echo >&2
  echo "next steps:" >&2
  echo "  activate in this terminal:  source ~/.claude-token" >&2
  echo "  in containers:              open a new shell (file is bind-mounted, already updated)" >&2
  echo "  persist for new terminals:  add 'source ~/.claude-token' to ~/.zshrc" >&2
}

# If a token was passed directly with --write, skip the auth flow entirely.
if [[ $WRITE -eq 1 && -n "$TOKEN" ]]; then
  save_token "$TOKEN"
  exit 0
fi

command -v docker >/dev/null 2>&1 || { echo "error: docker not on PATH" >&2; exit 1; }

NAME=cc
exists()  { [[ -n "$(docker ps -aq --filter "name=^/${NAME}$")" ]]; }
running() { [[ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" == "true" ]]; }

if ! exists; then
  echo "error: cc container not found — run 'd cc' once to create it, then retry" >&2
  exit 1
fi
if ! running; then
  echo "starting cc container…" >&2
  docker start "$NAME" >/dev/null
fi

echo "running claude setup-token inside cc — complete the browser/OAuth prompt." >&2
echo >&2

docker exec -it -u node "$NAME" bash -lc 'export PATH="$HOME/.local/bin:$PATH"; claude setup-token'
echo >&2

if [[ $WRITE -eq 1 ]]; then
  read -r -p "paste the token printed above: " TOKEN
  [[ -z "$TOKEN" ]] && { echo "error: no token entered" >&2; exit 1; }
  save_token "$TOKEN"
else
  echo "next steps:" >&2
  echo "  save the token:            d token --write \"<token>\"" >&2
  echo "  activate in this terminal: source ~/.claude-token" >&2
  echo "  persist for new terminals: add 'source ~/.claude-token' to ~/.zshrc" >&2
fi
