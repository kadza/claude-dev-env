#!/usr/bin/env bash
# Runs INSIDE the devcontainer as postCreateCommand (cwd = workspace folder).
# $1 is the project/container name, passed as ${localWorkspaceFolderBasename} — that
# devcontainer variable is only substituted in devcontainer.json, not visible here.
set -euo pipefail

NAME="${1:?usage: setup.sh <project-name>}"

# The Claude state mounts make Docker create these paths as root; reclaim them so
# bootstrap and Claude can write.
sudo chown "$(id -un):$(id -gn)" /home/vscode/.claude /home/vscode/.claude.json

# Claude Code CLI.
curl -fsSL https://claude.ai/install.sh | bash

# uv — project dependency management / running (uv run, uv sync).
curl -LsSf https://astral.sh/uv/install.sh | sh

# Neovim LSP servers + formatters into ~/.local/bin so the host-side .nvim.lua can
# `docker exec` them: pylsp + ruff (pulled in by python-lsp-ruff) + pyrefly.
pip install --upgrade pip
pip install python-lsp-server python-lsp-ruff pyrefly

# Wire ~/.claude to the config repo (general + python framework rules, settings).
/home/vscode/claude-dev-env/bootstrap.sh python "$NAME"
