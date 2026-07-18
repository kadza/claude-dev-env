# Worktree fix: mount the workspace at the host's own absolute path

Both templates add:
```json
"workspaceMount": "source=${localWorkspaceFolder},target=${localWorkspaceFolder},type=bind,consistency=cached",
"workspaceFolder": "${localWorkspaceFolder}",
```
Git worktree linkage is two small files holding absolute paths (`<main-repo>/.git/worktrees/<name>/gitdir` and `<worktree>/.git`), written by git running inside the container — so they hardcode whatever path the container sees the repo at. Standard devcontainer behavior mounts the repo at `/workspaces/<folder-name>`, a different absolute path than where it lives on the host, so the same linkage files resolve differently depending on which side is looking at them; `git worktree repair` can only rewrite for one side at a time, not both simultaneously. Using `${localWorkspaceFolder}` as both source and target makes the container see the repo at its actual host path, so absolute paths git writes resolve identically from both sides. This reuses syntax already validated by the same fix in another repo (`kite-lodz`); `consistency=cached` is a no-op outside Docker Desktop for Mac and costs nothing to include for portability. Known caveat: Docker Desktop for Mac (without OrbStack) or WSL path-translation quirks may not tolerate mounting at an arbitrary host-style absolute path as the container target.
