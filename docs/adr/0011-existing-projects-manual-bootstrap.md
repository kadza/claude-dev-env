# Existing projects: clone + bootstrap manually, no dedicated command

Existing projects keep their own per-project config repos for project-level config. Inside an existing project's devcontainer, clone this repo and run `bootstrap.sh <tech>` once — the user-level `~/.claude` stub then covers the general and framework layers with zero footprint in the project repo. This gives one home for general rules, with every improvement made once. Rejected: leaving existing projects out entirely (general-rule improvements would end up duplicated across configs).
