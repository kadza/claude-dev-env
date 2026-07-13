## Python

Use `uv` for dependency management and running code (`uv run`, `uv sync`) — don't call `pip` directly.

Add type hints to new functions. Run `ruff check` to lint and `uv run pytest` to run tests; both should
pass before you consider a change done. If the project has a `pyrefly.toml`, type-check with
`uv run pyrefly check` too.

Follow the project's existing layout (`src/` package, `tests/`) rather than restructuring it.
