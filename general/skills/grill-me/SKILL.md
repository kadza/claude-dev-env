---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down
each branch of the design tree, resolving dependencies between decisions one-by-one. For each question,
provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

## After the interview

Once all decisions are resolved, offer to write a `decisions.md` in the project root capturing each
decision with its rationale. This document is valuable as an implementation reference during coding, and
for sharing context with the team. Structure each entry as: the question that needed answering, the
decision made, and the reasoning behind it (including alternatives considered and why they were rejected).
