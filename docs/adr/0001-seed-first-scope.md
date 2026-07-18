# Seed-first scope; existing projects get a lighter manual path

The tool's job is to create a *seed* — a scaffolded project with a fully configured devcontainer — not to retrofit existing repos. The recurring pain being solved is starting new experiments with Claude Code already wired up, across a mix of solo and team repos, with config that must never be committed into project repos. Existing projects instead follow a lighter manual path: clone this repo inside their own devcontainer and run `bootstrap.sh` once (see [0011](./0011-existing-projects-manual-bootstrap.md)).
