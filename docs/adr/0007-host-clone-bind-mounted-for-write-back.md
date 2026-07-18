# One host clone, bind-mounted into every container (write-back)

There's one clone of this repo on the host (`~/claude-dev-env`); every template bind-mounts it, and bootstrap symlinks point at the mount. This means in-session changes (approved permissions, skill edits) write back to the repo instantly, and one `git pull` on the host updates every container. Rejected: per-container clones (in-session config changes die with the container unless pushed); a docker-volume clone (invisible from the host).
