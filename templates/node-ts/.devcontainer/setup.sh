#!/usr/bin/env bash
# Runs INSIDE the devcontainer as postCreateCommand (cwd = workspace folder).
# $1 is the project/container name, passed as ${localWorkspaceFolderBasename} — that
# devcontainer variable is only substituted in devcontainer.json, not visible here.
set -euo pipefail

NAME="${1:?usage: setup.sh <project-name>}"

# The Claude state mounts make Docker auto-create these paths as root; reclaim them so
# bootstrap and Claude can write.
sudo chown "$(id -un):$(id -gn)" /home/node/.claude /home/node/.claude.json

# Claude Code CLI.
curl -fsSL https://claude.ai/install.sh | bash

# Project dependencies, so oxlint/oxfmt land in node_modules/.bin — the host-side
# .nvim.lua resolves them there (local_bin) rather than globally. Skipped (not failed) when
# there's no root package.json — e.g. a cloned repo that nests its Node project in a subdirectory
# (like api/) — since `set -euo pipefail` would otherwise abort bootstrap.sh below too. In that
# case, `cd` into the real project dir and run `npm install` yourself once inside the container.
[[ -f package.json ]] && npm install

# Neovim LSP server + formatter, installed globally so the host-side .nvim.lua can
# `docker exec` them by name: vtsls + prettier. No sudo needed — this image's npm
# global prefix (NPM_GLOBAL) is already writable by the node user and on PATH.
npm install -g typescript @vtsls/language-server prettier

# Wire ~/.claude to the config repo (general + node-ts framework rules, settings).
/home/node/claude-dev-env/bootstrap.sh node-ts "$NAME"
