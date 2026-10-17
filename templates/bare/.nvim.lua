-- Host-side Neovim config for driving shellcheck/shfmt that live *inside* this project's
-- devcontainer (via `docker exec`). Auto-sourced by Neovim when `exrc` is enabled and this file
-- is trusted. Requires conform.nvim (formatting) and nvim-lint (diagnostics).
--
-- The container is named after the project folder (devcontainer.json: `--name
-- ${localWorkspaceFolderBasename}`), so we derive its name from the cwd basename rather than
-- hardcoding it — keeps this template generic. Override with CLAUDE_DEV_CONTAINER if names
-- diverge.
--
-- This template has no language runtime, so there's no LSP server here (bash-language-server
-- needs node, which this template deliberately doesn't install) — just shellcheck for
-- diagnostics and shfmt for formatting, both plain apt packages inside the container.
--
-- exrc only sources this file when nvim is started with the repo root as cwd, so getcwd() below
-- is reliable as "the repo root" — and, since the devcontainer bind-mounts the repo at this same
-- absolute path, it's also the repo root *inside* the container.

local conform = require("conform")
local lint = require("lint")

local function find_workspace_root(start)
	return vim.fs.root(start, { ".devcontainer", ".git" }) or start
end

local root = find_workspace_root(vim.fn.getcwd())
local container = os.getenv("CLAUDE_DEV_CONTAINER") or vim.fn.fnamemodify(root, ":t")

-- shfmt formats over stdin; conform substitutes the literal "$FILENAME" token itself, so it can
-- sit inside a static args table without a wrapper function.
conform.formatters.shfmt = {
	command = "docker",
	args = { "exec", "-i", "-u", "vscode", "-e", "HOME=/home/vscode", "-w", root, container, "shfmt", "-filename", "$FILENAME" },
	stdin = true,
}
conform.formatters_by_ft.sh = { "shfmt" }
conform.formatters_by_ft.bash = { "shfmt" }

-- nvim-lint's built-in shellcheck linter already runs over stdin with gcc-format output; just
-- point its cmd/args at `docker exec` instead of a local shellcheck binary.
lint.linters.shellcheck.cmd = "docker"
lint.linters.shellcheck.args = {
	"exec",
	"-i",
	"-u",
	"vscode",
	"-e",
	"HOME=/home/vscode",
	"-w",
	root,
	container,
	"shellcheck",
	"--format=gcc",
	"-",
}
lint.linters_by_ft.sh = { "shellcheck" }
lint.linters_by_ft.bash = { "shellcheck" }
