# Clone leaves injected env files untracked, makes no commit

Injected `.devcontainer`/`.claude` files are copied into the working tree and left untracked — `clone` makes no commit. The clone carries a live upstream remote, so making no commit is the simplest guarantee that env files never get pushed. The cost is a dirty `git status` (untracked/modified paths), which is acceptable and documented. Rejected: registering the files in `.git/info/exclude` (cleaner `git status`, but more machinery than needed); a local-only branch (heavier, and still pushable by mistake).
