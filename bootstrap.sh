#!/usr/bin/env bash
# Runs INSIDE a devcontainer. Wires ~/.claude to the bind-mounted config repo.
# Usage: bootstrap.sh [<tech>] [<project>]
#   <tech>    names a dir under frameworks/; omit for general-only (e.g. the `cc` container).
#   <project> project name for the shell prompt; omit to leave the prompt untouched.
# Idempotent — safe to re-run anytime (e.g. after adding a skill).
set -euo pipefail

TECH="${1:-}"
PROJECT="${2:-}"

# REPO = the dir this script lives in = the bind-mounted config repo. Never hardcoded.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# TECH is optional. With a tech we layer frameworks/<tech> on top of general; with none
# (e.g. the general-purpose `cc` container) we wire only the general layer.
FW=""
if [[ -n "$TECH" ]]; then
  FW="$REPO/frameworks/$TECH"
  if [[ ! -d "$FW" ]]; then
    echo "error: unknown tech '$TECH' — no such dir $FW" >&2
    echo "available frameworks:" >&2
    ls -1 "$REPO/frameworks" >&2 || true
    exit 1
  fi
fi

CLAUDE_HOME="$HOME/.claude"
mkdir -p "$CLAUDE_HOME/skills"

# 1. CLAUDE.md stub — absolute @imports into the mounted repo (overwrite each run). The
#    framework import is included only when a tech was given.
{
  echo "@$REPO/general/CLAUDE.md"
  [[ -n "$FW" ]] && echo "@$FW/CLAUDE.md"
} > "$CLAUDE_HOME/CLAUDE.md"

# 2. General settings — symlink so in-session approvals write back to the repo.
ln -sfn "$REPO/general/settings.json" "$CLAUDE_HOME/settings.json"

# 3. Skills — symlink each general + framework skill dir into ~/.claude/skills/.
skill_globs=("$REPO/general/skills/"*/)
[[ -n "$FW" ]] && skill_globs+=("$FW/skills/"*/)
for dir in "${skill_globs[@]}"; do
  [[ -d "$dir" ]] || continue          # skip when a skills/ dir is empty (glob doesn't expand)
  name="$(basename "$dir")"
  ln -sfn "${dir%/}" "$CLAUDE_HOME/skills/$name"
done

# 4. UI defaults — merge general/claude.json (theme, onboarding) into ~/.claude.json without
#    clobbering keys Claude manages (userID, machineID, history, per-project trust). Only fills
#    MISSING keys, so a later manual theme change sticks. Runs every bootstrap → self-healing.
DEFAULTS="$REPO/general/claude.json"
TARGET="$HOME/.claude.json"
if [[ -f "$DEFAULTS" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    MERGER=(python3 - "$DEFAULTS" "$TARGET"); MERGE_IMPL='python3'
  elif command -v node >/dev/null 2>&1; then
    MERGER=(node -e '
      const fs=require("fs"),[d,t]=process.argv.slice(1);
      const def=JSON.parse(fs.readFileSync(d,"utf8"));
      let cur={}; try{cur=JSON.parse(fs.readFileSync(t,"utf8"))}catch(e){}
      for(const k of Object.keys(def)) if(!(k in cur)) cur[k]=def[k];
      fs.writeFileSync(t, JSON.stringify(cur,null,2)+"\n");
    ' "$DEFAULTS" "$TARGET"); MERGE_IMPL='node'
  else
    MERGE_IMPL=''
    echo "bootstrap: warn — no python3/node found; skipped ~/.claude.json defaults" >&2
  fi
  if [[ "$MERGE_IMPL" == 'python3' ]]; then
    "${MERGER[@]}" <<'PY'
import json, sys, pathlib
defp, tgtp = sys.argv[1], sys.argv[2]
defaults = json.load(open(defp))
tgt = pathlib.Path(tgtp)
try:
    cur = json.loads(tgt.read_text())
except Exception:
    cur = {}
for k, v in defaults.items():
    cur.setdefault(k, v)
tgt.write_text(json.dumps(cur, indent=2) + "\n")
PY
  elif [[ "$MERGE_IMPL" == 'node' ]]; then
    "${MERGER[@]}"
  fi
fi

# 5. Shell prompt — surface the project name so open containers are easy to tell apart. The
#    container user stays node/vscode (renaming it isn't cheap, and --network=host blocks setting
#    the hostname), so we put the project name where the host normally goes: the prompt reads
#    "node@<project>:~/…". The PS1 lives in its own file (overwritten each run → self-updating) and
#    ~/.bashrc sources it once. No-op when no project name was passed (e.g. the `cc` container).
if [[ -n "$PROJECT" ]]; then
  PROMPT_FILE="$HOME/.claude-dev-env-prompt.sh"
  # Single-quoted PS1 so \u \w \e \$ reach the file as literal escapes for bash to expand at prompt
  # time; only $PROJECT is interpolated now. (\\\$ → literal \$, i.e. $ for users / # for root.)
  printf '%s\n' "export PS1='\[\e[1;36m\]\u@$PROJECT\[\e[0m\]:\w\\\$ '" > "$PROMPT_FILE"
  if ! grep -qF 'claude-dev-env-prompt.sh' "$HOME/.bashrc" 2>/dev/null; then
    printf '%s\n' '[ -f "$HOME/.claude-dev-env-prompt.sh" ] && . "$HOME/.claude-dev-env-prompt.sh"' >> "$HOME/.bashrc"
  fi
fi

echo "bootstrap: wired $CLAUDE_HOME${TECH:+ for tech '$TECH'}${PROJECT:+ (prompt '$PROJECT')} from $REPO"
