# Seed tool is a small CLI script, not a published template mechanism

`seed <tech> <name>` is a small script in this repo: it creates `~/projects/<name>` from `templates/<tech>/`, `git init`s, runs `devcontainer up`, and execs a shell inside. This is a single-user tool, so there's no publishing overhead. Rejected: the devcontainer templates registry (needs publishing machinery and still requires a wrapper script); GitHub template repos (couples seeding to GitHub and scatters templates across repos).
