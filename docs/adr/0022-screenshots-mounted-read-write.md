# Screenshot folder mounted read-write

The screenshot folder is mounted read-write (plain `type=bind`; `-v` for `cc`), not read-only, because Claude needs to delete a screenshot after reading it ([0023](./0023-screenshots-deleted-after-read.md)). Rejected: read-only — safer against accidental clobber, but blocks the cleanup step; the clobber risk was accepted in exchange for auto-cleanup.
