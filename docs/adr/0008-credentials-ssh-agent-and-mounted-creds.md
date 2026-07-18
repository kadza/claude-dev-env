# Credentials: SSH agent forwarding + mounted Claude credential file

Git auth uses SSH agent forwarding; Claude Code auth uses the host's credential file mounted into the container home by the template. No secrets baked into images, no login dance per container — the only host prerequisite is an `ssh-agent` running with the key loaded. Rejected: a fresh `claude login` per container (too much friction); PAT/tokens passed via env vars (larger leak surface).
