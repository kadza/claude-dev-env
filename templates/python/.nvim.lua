-- Host-side Neovim config for driving the LSP/formatters that live *inside* this
-- project's devcontainer (via `docker exec`). Auto-sourced by Neovim when `exrc` is
-- enabled and this file is trusted. Requires nvim-lspconfig, cmp_nvim_lsp, and conform.nvim.
--
-- The devcontainer is named after the project folder (see .devcontainer/devcontainer.json:
-- `--name ${localWorkspaceFolderBasename}`), so we derive the container name from the current
-- working directory's basename rather than hardcoding it — that keeps this template generic
-- across every seeded project. Override with CLAUDE_DEV_CONTAINER if the names ever diverge.
-- The LSP servers/formatters are installed into /home/vscode/.local/bin by the container's
-- postCreateCommand (`uv tool install ...`).

local container = os.getenv("CLAUDE_DEV_CONTAINER") or vim.fn.fnamemodify(vim.fn.getcwd(), ":t")

local function docker_exec(bin, ...)
	return { "docker", "exec", "-i", "-u", "vscode", "-e", "HOME=/home/vscode", container, bin, ... }
end

local lspconfig = require("lspconfig")
local cmp_nvim_lsp = require("cmp_nvim_lsp")
local conform = require("conform")
local capabilities = cmp_nvim_lsp.default_capabilities()

lspconfig.pylsp.setup({
	capabilities = capabilities,
	cmd = docker_exec("/home/vscode/.local/bin/pylsp"),
	root_dir = lspconfig.util.root_pattern(".git", "pyproject.toml", "setup.py"),
	settings = {
		pylsp = {
			plugins = {
				ruff = { enabled = true },
				pyflakes = { enabled = false },
				pycodestyle = { enabled = false },
				pylsp_mypy = { enabled = false },
				autopep8 = { enabled = false },
			},
		},
	},
})

local configs = require("lspconfig.configs")
if not configs.pyrefly then
	configs.pyrefly = {
		default_config = {
			cmd = docker_exec("/home/vscode/.local/bin/pyrefly", "lsp"),
			filetypes = { "python" },
			root_dir = lspconfig.util.root_pattern(".git", "pyproject.toml", "setup.py"),
			single_file_support = true,
		},
	}
end

lspconfig.pyrefly.setup({ capabilities = capabilities })

conform.formatters.ruff_format = {
	command = "docker",
	args = {
		"exec",
		"-i",
		"-u",
		"vscode",
		"-e",
		"HOME=/home/vscode",
		container,
		"/home/vscode/.local/bin/ruff",
		"format",
		"--stdin-filename",
		"$FILENAME",
		"-",
	},
	stdin = true,
}

conform.formatters_by_ft.python = { "ruff_fix", "ruff_format" }
