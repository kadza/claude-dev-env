-- Neovim sends its own HOST pid as processId, but these servers run inside the container's
-- separate PID namespace via docker exec. vscode-languageserver (vtsls, and oxlint if it's built
-- on the same base) polls that pid periodically per the LSP spec and exits once it looks dead —
-- which it always does here, since the host pid doesn't exist in the container's namespace. A
-- null processId means "no parent to monitor" and skips that check entirely.
local function clear_process_id(params)
	params.processId = vim.NIL
end

-- root_markers intentionally omitted: inherit the global config's { ".git" } (repo-root, single
-- instance for the whole monorepo) rather than duplicating it here where it could drift.
vim.lsp.config("vtsls", {
	cmd = docker_exec("vtsls", "--stdio"),
	before_init = clear_process_id,
})

-- oxlint provides linting diagnostics/code actions (replaces eslint in this repo). Config is
-- .oxlintrc.json at the repo root, so root it there rather than per-package like vtsls.
vim.lsp.config("oxlint", {
	cmd = docker_exec(local_bin("oxlint"), "--lsp"),
	filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
	root_markers = { ".oxlintrc.json", ".git" },
	before_init = clear_process_id,
})
vim.lsp.enable("oxlint")

conform.formatters.oxfmt = {
	command = "docker",
	args = {
		"exec",
		"-i",
		"-u",
		"node",
		"-e",
		"HOME=/home/node",
		container,
		local_bin("oxfmt"),
		"--stdin-filepath",
		"$FILENAME",
	},
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
