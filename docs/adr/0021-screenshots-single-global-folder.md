# One global screenshot folder, not per-project

A single global `~/claude-shots` on the host is mounted into every container (`cc` and all seeded/cloned projects), rather than a per-project folder. Screenshots are transient scratch, not per-project artifacts, and the destination is already chosen manually in the macOS menu each time — one folder means one `Other Location…` pick, one `mkdir`, and it works everywhere. Rejected: a per-project folder (`~/claude-shots/<project>`) — would force re-picking the destination in the macOS menu on every project switch, defeating the one-time-setup goal.
