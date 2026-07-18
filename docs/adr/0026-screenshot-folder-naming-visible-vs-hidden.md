# Screenshot folder: visible on the host, hidden in the container

The host folder is `~/claude-shots` (visible); the container target is `~/.claude-shots` (hidden). The macOS "Other Location…" picker doesn't surface hidden dot-folders without `Cmd+Shift+.`, so the host folder must be visible to be pickable, while a dot-folder keeps the container's `$HOME` tidy. Rejected: both visible (symmetric, but one extra visible directory cluttering the container home); both hidden (the host folder becomes awkward to select in the Finder dialog).
