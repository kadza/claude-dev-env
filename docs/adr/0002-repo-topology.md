# This repo holds general + framework + templates only; project config lives per-project

`claude-dev-env` holds the general and framework layers plus `templates/`, `seed.sh`, and `bootstrap.sh` — nothing project-specific. Project-specific config lives in a small dedicated repo per project, so ownership stays clean and a project's config can be shared independently of this one. Rejected: a monorepo with a `projects/` directory (mixes unrelated projects together); a repo-per-framework (version skew, N clones per container, no benefit for a single user).
