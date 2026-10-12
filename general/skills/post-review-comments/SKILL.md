---
name: post-review-comments
description: Turn a list of code-review findings (e.g. from code-review or code-review-with-spec) into inline comments on a GitHub PR, one finding at a time, with consistent concise wording and full coverage of repeated findings. Use when the user wants to post/push review findings as PR comments, or asks to work through a review list "one at a time" / "go with N".
---

Converts review findings into inline `gh api` PR comments. This is a posting workflow, not a review-generation one — it assumes findings already exist (from `code-review`, `code-review-with-spec`, or a pasted list).

## Process

### 1. Pin the PR and the head commit

Resolve owner/repo from `git remote -v` if not given. Get the PR number from the user.

```
gh pr view <number> --json headRefOid,baseRefName,headRefName,state,title
```

`headRefOid` is the `commit_id` every inline comment anchors to. If the user says they pushed new commits since you last checked, re-run this before posting — a stale `commit_id` anchors comments to an outdated diff.

### 2. Work one finding at a time

Findings are posted in whatever order the user directs (they may jump around — "go with 6", "now 3"), not necessarily top-to-bottom through the list. Don't post ahead of what's been asked for.

### 3. Verify before posting — don't trust the summary

A review summary's cited `file:line` and "identical" claims can be stale or imprecise (summaries are written against a diff snapshot, and sub-agents paraphrase). Before posting:

- Read the actual file at the cited line, and/or `gh pr diff <number>` for that file, to confirm the line number and content genuinely match.
- If the summary says a pattern is "identical" across files, confirm that byte-for-byte; if it's only approximately the same (e.g. same property, different value), say so in the comment rather than repeating "identical".
- Use the diff's `@@ -a,b +c,d @@` hunk header to compute the correct new-file line number for `side: "RIGHT"` (or old-file line for `side: "LEFT"` on a removed/changed line).

### 4. Enumerate every occurrence of a repeated finding

If a finding says a pattern "repeats N times" or cites "e.g." examples, don't comment only on the cited examples — find every real occurrence (grep the full diff or the affected files) and post on all of them. The summary's examples are illustrative, not exhaustive.

### 5. Draft the comment: short, problem + fix only

State what's wrong and how to fix it. Don't restate which pattern/component was used vs. should be used as a label (no "raw X instead of Y" framing) — just the concrete defect and the concrete remedy. Keep wording identical across every occurrence of the same finding unless a specific occurrence genuinely needs a different fix (e.g. a checkbox among otherwise-text inputs) — then give that subset its own short body.

### 6. Post via the GitHub API — not `gh pr comment`

`gh pr comment` only posts issue-level (non-inline) comments. Use the review-comment endpoint directly:

```
gh api repos/<owner>/<repo>/pulls/<number>/comments \
  -f body="..." \
  -f commit_id="<headRefOid>" \
  -f path="<file>" \
  -F line=<n> \
  -f side="RIGHT"
```

For a finding with many occurrences, loop over a list of `path:line` pairs with the same `body`, pausing briefly between calls.

### 7. Revise by editing in place, never delete-and-recreate

If the user asks to change wording after posting, `PATCH` the existing comment — deleting and reposting loses the comment's thread position and any replies.

```
gh api -X PATCH repos/<owner>/<repo>/pulls/comments/<id> -f body="..."
```

To find a comment's id again, list and filter on `path`/`line`/a body substring:

```
gh api repos/<owner>/<repo>/pulls/<number>/comments --paginate
```

### 8. Confirm before moving on

After posting (or revising) a finding, report what was posted (with the comment URL) and wait for direction on the next one — don't bulk-post the rest of the list unprompted.
