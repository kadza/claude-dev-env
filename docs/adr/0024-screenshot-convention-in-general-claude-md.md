# Screenshot convention documented in general/CLAUDE.md, not a skill

The "read the newest file in `~/.claude-shots/`, then delete it" convention lives as a short section in `general/CLAUDE.md`, which is `@import`ed into every container, so it fires implicitly on "look at my screenshot" with no re-explaining — this is what makes the integration feel native rather than bolted on. Rejected: a dedicated skill (heavier, only fires on explicit invocation — overkill for a one-line convention); README-only with the user re-explaining the path each session (least integrated option).
