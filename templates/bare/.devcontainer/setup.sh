#!/usr/bin/env bash
# Runs INSIDE the devcontainer as postCreateCommand (cwd = workspace folder).
# $1 is the project/container name, passed as ${localWorkspaceFolderBasename} — that
# devcontainer variable is only substituted in devcontainer.json, not visible here.
set -euo pipefail

NAME="${1:?usage: setup.sh <project-name>}"

# The Claude state mounts make Docker auto-create these paths as root; reclaim them so
# bootstrap and Claude can write.
sudo chown "$(id -un):$(id -gn)" /home/vscode/.claude /home/vscode/.claude.json

# Claude Code CLI.
curl -fsSL https://claude.ai/install.sh | bash

# shellcheck + shfmt, installed globally so the host-side .nvim.lua can `docker exec` them by
# name: shellcheck for lint diagnostics, shfmt for formatting. Both are plain apt packages here —
# no node/python toolchain needed to get shell linting/formatting.
sudo apt-get update -qq && sudo apt-get install -y -qq --no-install-recommends shellcheck shfmt

# Wire ~/.claude to the config repo — general layer only, no framework, since this template has
# no language runtime (see frameworks/ — there's nothing to layer in here).
/home/vscode/claude-dev-env/bootstrap.sh "" "$NAME"
