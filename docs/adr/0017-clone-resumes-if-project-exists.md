# Clone resumes if the project already exists, like seed

If `~/projects/<name>` already exists, `clone` resumes exactly like `seed` — it skips the clone + inject steps and goes straight to `devcontainer up` + exec. This keeps a consistent mental model with `seed`: re-running is how you reconnect after closing the shell. It deliberately does not re-pull — updating the code is the user's own `git pull` inside the container. Rejected: erroring out on an existing directory (less convenient for the common reconnect case).
