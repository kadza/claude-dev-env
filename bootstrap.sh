#!/usr/bin/env bash
# Runs INSIDE a devcontainer. Wires ~/.claude to the bind-mounted config repo.
# Usage: bootstrap.sh <tech>   (<tech> names a dir under frameworks/)
# Idempotent — safe to re-run anytime (e.g. after adding a skill).
set -euo pipefail

TECH="${1:-}"
if [[ -z "$TECH" ]]; then
  echo "usage: bootstrap.sh <tech>" >&2
  exit 1
fi

# REPO = the dir this script lives in = the bind-mounted config repo. Never hardcoded.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FW="$REPO/frameworks/$TECH"
if [[ ! -d "$FW" ]]; then
  echo "error: unknown tech '$TECH' — no such dir $FW" >&2
  echo "available frameworks:" >&2
  ls -1 "$REPO/frameworks" >&2 || true
  exit 1
fi

CLAUDE_HOME="$HOME/.claude"
mkdir -p "$CLAUDE_HOME/skills"

# 1. CLAUDE.md stub — two absolute @imports into the mounted repo (overwrite each run).
cat > "$CLAUDE_HOME/CLAUDE.md" <<EOF
@$REPO/general/CLAUDE.md
@$FW/CLAUDE.md
EOF

# 2. General settings — symlink so in-session approvals write back to the repo.
ln -sfn "$REPO/general/settings.json" "$CLAUDE_HOME/settings.json"

# 3. Skills — symlink each general + framework skill dir into ~/.claude/skills/.
for dir in "$REPO/general/skills/"*/ "$FW/skills/"*/; do
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

echo "bootstrap: wired $CLAUDE_HOME for tech '$TECH' from $REPO"
