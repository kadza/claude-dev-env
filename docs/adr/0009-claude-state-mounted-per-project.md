# Claude runtime state mounted per project, survives rebuilds

Templates mount a host directory (`~/claude-state/<project>`) over the container's `~/.claude/projects`, so memory/history/trust survive container rebuilds and stay inspectable from the host. Long-lived seeds accumulate valuable project memory that shouldn't be thrown away on every rebuild. Rejected: named volumes (hidden, prunable); fully ephemeral state (memory lost every rebuild).
