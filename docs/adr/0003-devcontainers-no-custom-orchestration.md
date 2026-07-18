# Standard devcontainers, no custom orchestration

`seed.sh` creates the project directory on the host; standard devcontainer machinery bind-mounts it in. No custom Docker orchestration. Rejected: named volumes + push-to-git (unpushed work is at risk and invisible from the host); fully ephemeral containers (too easy to lose work).
