-- Host-side Neovim config for driving the LSP/formatters that live *inside* this project's
-- devcontainer (via `docker exec`). Auto-sourced by Neovim when `exrc` is enabled and this file is
-- trusted. Requires conform.nvim.
--
-- The container is named after the project folder (devcontainer.json: `--name
-- ${localWorkspaceFolderBasename}`), so we derive its name from the cwd basename rather than
-- hardcoding it — keeps this template generic. Override with CLAUDE_DEV_CONTAINER if names diverge.
-- oxlint/oxfmt/tsc are run from each subpackage's own node_modules/.bin instead, so editor
-- lint/format/type-check stay pinned to the exact versions CI and lint-staged use, not a global
-- install.
--
-- exrc only sources this file when nvim is started with the repo root as cwd, so getcwd() below
-- is reliable as "the repo root" — and, since the devcontainer bind-mounts the repo at this same
-- absolute path, it's also the repo root *inside* the container.

local conform = require("conform")

local function find_workspace_root(start)
	return vim.fs.root(start, { ".devcontainer", ".git" }) or start
end

local root = find_workspace_root(vim.fn.getcwd())
local container = os.getenv("CLAUDE_DEV_CONTAINER") or vim.fn.fnamemodify(root, ":t")

local function docker_exec(bin, ...)
	return { "docker", "exec", "-i", "-u", "node", "-e", "HOME=/home/node", "-w", root, container, bin, ... }
end

local function local_bin(name)
	return root .. "/node_modules/.bin/" .. name
end

-- Neovim sends its own HOST pid as processId, but these servers run inside the container's
-- separate PID namespace via docker exec. Servers that poll that pid per the LSP spec exit once
-- it looks dead — which it always does here, since the host pid doesn't exist in the container's
-- namespace. A null processId means "no parent to monitor" and skips that check entirely.
local function clear_process_id(params)
	params.processId = vim.NIL
end

-- tsc and oxlint below each negotiate their own offset_encoding independently (one ends up on
-- utf-8, the other falls back to the LSP-spec default utf-16), which trips Neovim's "multiple
-- different client offset_encodings" warning once both attach to the same buffer. Only advertise
-- utf-16 — the one encoding every LSP-compliant server must support — so both converge on it.
local capabilities = vim.tbl_deep_extend("force", vim.lsp.protocol.make_client_capabilities(), {
	general = { positionEncodings = { "utf-16" } },
})

-- tsc's own --lsp mode replaces vtsls here: TypeScript's native (Go-rewrite) compiler speaking
-- LSP directly, no tsserver-protocol translation layer. root_dir walks up to the nearest
-- pnpm-lock.yaml so each subpackage (api/, webhooks/, ...) gets its own instance, rooted and
-- type-checked against its own installed TypeScript rather than a shared/wrong one.
vim.lsp.config("tsc", {
	cmd = function(dispatchers, config)
		local lsp_root = (config and config.root_dir) or root
		return vim.lsp.rpc.start({
			"docker",
			"exec",
			"-i",
			"-u",
			"node",
			"-e",
			"HOME=/home/node",
			"-w",
			lsp_root,
			container,
			lsp_root .. "/node_modules/.bin/tsgo",
			"--lsp",
			"--stdio",
		}, dispatchers)
	end,
	filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
	root_dir = function(bufnr, on_dir)
		on_dir(vim.fs.root(bufnr, { "pnpm-lock.yaml" }))
	end,
	before_init = clear_process_id,
	capabilities = capabilities,
})
vim.lsp.enable("tsc")

-- vim.lsp.enable("vtsls", false) loses a load-order race against the personal global config's own
-- vtsls enable (same class of issue as the eslint_d re-apply below) — so instead of fighting that
-- race, just kill it the moment it attaches to a buffer in this project; our tsc client replaces it.
vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if client and client.name == "vtsls" then
			client:stop(true)
		end
	end,
})

-- oxlint provides linting diagnostics/code actions (replaces eslint in this repo). Only api/ has
-- .oxlintrc.json and its own oxlint install right now (unlike oxfmt, which every subpackage
-- runs), so point straight at api/'s node_modules/.bin instead of the nonexistent root one.
vim.lsp.config("oxlint", {
	cmd = docker_exec(root .. "/node_modules/.bin/oxlint", "--lsp"),
	filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
	root_markers = { ".oxlintrc.json", ".git" },
	before_init = clear_process_id,
	capabilities = capabilities,
})
vim.lsp.enable("oxlint")

-- This is a monorepo with no root node_modules (api/, webhooks/, etc. each install their own
-- deps), so local_bin("oxfmt") — rooted at getcwd() — doesn't exist for most buffers. Walk up
-- from the buffer being formatted to find its nearest node_modules/.bin/oxfmt instead.
local function find_oxfmt(start_dir)
	local node_modules = vim.fs.find("node_modules", { upward = true, path = start_dir })[1]
	if node_modules then
		local candidate = node_modules .. "/.bin/oxfmt"
		if vim.uv.fs_stat(candidate) then
			return candidate
		end
	end
	return local_bin("oxfmt")
end

conform.formatters.oxfmt = {
	command = "docker",
	args = function(self, ctx)
		return {
			"exec",
			"-i",
			"-u",
			"node",
			"-e",
			"HOME=/home/node",
			container,
			find_oxfmt(vim.fs.dirname(ctx.filename)),
			"--stdin-filepath",
			"$FILENAME",
		}
	end,
	stdin = true,
}

conform.formatters_by_ft.typescript = { "oxfmt" }
conform.formatters_by_ft.typescriptreact = { "oxfmt" }
conform.formatters_by_ft.javascript = { "oxfmt" }
conform.formatters_by_ft.javascriptreact = { "oxfmt" }

-- This repo has no eslint at all (fully migrated to oxlint — see .oxlintrc.json), so a global
-- eslint_d nvim-lint linter has nothing valid to run here. The oxlint LSP client above already
-- gives live diagnostics, so just turn eslint_d off for this project rather than duplicate it.
-- Applied on FileType (not just once at startup): whatever registers eslint_d re-applies it per
-- buffer too, so ours must run after that on every buffer it opens, not just the first one.
local lint_fts = { "javascript", "javascriptreact", "typescript", "typescriptreact" }

local function disable_eslint_d()
	local ok, lint = pcall(require, "lint")
	if ok then
		lint.linters_by_ft = lint.linters_by_ft or {}
		for _, ft in ipairs(lint_fts) do
			lint.linters_by_ft[ft] = {}
		end
	end
end

disable_eslint_d()
vim.api.nvim_create_autocmd("FileType", { pattern = lint_fts, callback = disable_eslint_d })
