#!/usr/bin/env bash
# Runs on the HOST. One-shot setup for claude-dev-env:
#   1. symlinks the standalone commands (d, cc) into a bin dir on your PATH. Everything else is a
#      `d` subcommand — `d seed`, `d clone`, `d up`, `d unseed` — so only these two need a name.
#   2. writes a managed block to your shell profile exporting CLAUDE_DEV_ENV (and prepending the bin
#      dir to PATH if it isn't already reachable), so manual reconnects (`devcontainer up`,
#      `devpod ssh`) resolve the config-repo mount instead of failing with an empty mount source.
# Idempotent — re-run anytime: links are refreshed and the profile block is rewritten in place.
#
# Usage: setup.sh [BIN_DIR]            (BIN_DIR default: ~/.local/bin)
#        PROFILE=~/.bashrc setup.sh    (override the shell profile; default: ~/.zshrc)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${1:-$HOME/.local/bin}"
PROFILE="${PROFILE:-$HOME/.zshrc}"

[[ -d "$BIN" ]] || { echo "error: $BIN does not exist (create it or pass an existing dir)" >&2; exit 1; }

# --- 1. commands ---------------------------------------------------------------------------------
# Only d + cc are standalone; the rest are reached through `d <cmd>`.
for name in d cc; do
  ln -sfn "$REPO/$name.sh" "$BIN/$name"
  echo "linked $BIN/$name -> $REPO/$name.sh"
done
# Clean up links from the old layout (when seed/clone/unseed were standalone) so they don't linger
# as stale copies. Only remove links that point back at this repo — never touch unrelated binaries.
for old in seed clone unseed; do
  link="$BIN/$old"
  if [[ -L "$link" && "$(readlink "$link")" == "$REPO/$old.sh" ]]; then
    rm -f "$link"
    echo "removed old $link (use 'd $old' instead)"
  fi
done

# --- 2. shell profile ----------------------------------------------------------------------------
# A single managed block, delimited by markers and rewritten in place, so re-runs never duplicate.
BEGIN="# >>> claude-dev-env >>>"
END="# <<< claude-dev-env <<<"

block="$BEGIN"$'\n'
block+="export CLAUDE_DEV_ENV=\"$REPO\""$'\n'
case ":$PATH:" in
  *":$BIN:"*) : ;;                                   # bin dir already reachable — no PATH line
  *) block+="export PATH=\"$BIN:\$PATH\""$'\n' ;;
esac
# Drop any shadowing alias/function named d or cc (e.g. oh-my-zsh's `d=dirs -v`) so our commands
# win. In zsh alias expansion beats a PATH lookup, so a symlink alone isn't enough — this block is
# appended at the end of the profile, i.e. after oh-my-zsh has defined its aliases.
block+="unalias d cc 2>/dev/null; unfunction d cc 2>/dev/null; :"$'\n'
block+="$END"

touch "$PROFILE"
grep -qF "$BEGIN" "$PROFILE" && verb="updated" || verb="added"
# Drop any existing block (markers included) and strip trailing blank lines, so re-runs replace the
# block in place and never accumulate gaps. Then re-append the fresh block after one blank line.
tmp="$(mktemp)"
awk -v b="$BEGIN" -v e="$END" '
  $0==b {skip=1}
  !skip {a[++n]=$0}
  $0==e {skip=0}
  END {last=n; while (last>0 && a[last]=="") last--; for (i=1;i<=last;i++) print a[i]}
' "$PROFILE" > "$tmp"
mv "$tmp" "$PROFILE"
printf '\n%s\n' "$block" >> "$PROFILE"
echo "$verb claude-dev-env block in $PROFILE"

# --- 3. screenshot inbox -------------------------------------------------------------------------
# The shared, global folder macOS screenshots land in; every container mounts it at ~/.claude-shots.
# Create it here so the bind mount resolves (bring-up scripts also create it defensively).
mkdir -p "$HOME/claude-shots"
echo "created $HOME/claude-shots (shared screenshot inbox)"

# --- next steps ----------------------------------------------------------------------------------
echo
echo "done — open a new shell, or: source \"$PROFILE\""
echo
echo "screenshots: to show Claude a screenshot, save it into ~/claude-shots. Add that folder once as a"
echo "  destination — Cmd+Shift+5 → Options → Save to → Other Location… → ~/claude-shots — then pick it"
echo "  per shot. Claude reads the newest file (at ~/.claude-shots in the container) and deletes it after."
[[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] || cat >&2 <<EOF
note: CLAUDE_CODE_OAUTH_TOKEN is unset. Mint one once and add it to $PROFILE so containers start
      authenticated:  export CLAUDE_CODE_OAUTH_TOKEN="\$(claude setup-token)"
EOF
