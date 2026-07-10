#!/usr/bin/env bash
# Runs on the HOST. Symlinks the host commands (seed, clone, unseed, cc) into a bin dir on your PATH.
# Idempotent — re-run anytime; existing links are refreshed.
# Usage: install-commands.sh [BIN_DIR]   (default: ~/.local/bin)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${1:-$HOME/.local/bin}"

[[ -d "$BIN" ]] || { echo "error: $BIN does not exist (create it or pass an existing dir)" >&2; exit 1; }

for name in seed clone unseed cc; do
  ln -sfn "$REPO/$name.sh" "$BIN/$name"
  echo "linked $BIN/$name -> $REPO/$name.sh"
done

# PATH check — warn (don't fail) if the chosen bin dir isn't reachable.
case ":$PATH:" in
  *":$BIN:"*) : ;;
  *) echo "note: $BIN is not on your PATH. Add this to your shell profile (~/.zshrc or ~/.bash_profile):" >&2
     echo "      export PATH=\"$BIN:\$PATH\"" >&2 ;;
esac
