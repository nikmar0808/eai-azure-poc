# ADR-001: POC repositories are fresh-history copies of the working repositories

## Status
Accepted — 2026-09-23

## Context
The POC work runs on clones of the learner's working Enterprise Integration
repositories. A clone made with `git
clone` carries the entire commit history of the original, including any
commit that ever contained a secret or a real identifier, even if a later
commit removed it — the value remains reachable in the clone's `.git`
history regardless of what the current file content shows.

## Decision
Every POC clone is created with `git archive` against a single commit of
the working repository, producing a working tree
with no `.git` history at all. `git init` then starts a genuinely fresh
history in the new repository. No commit from the original repository,
and therefore no secret or identifier that may exist only in an old
commit, is reachable from the new repository at any point.

## Consequences
- The scrub only has to clear the current file content, not
  every historical revision of every file — a materially smaller task.
- The new repository's history starts empty; there is no `git blame`
  trail into the original project's authorship or dates. This is
  accepted, since the POC repository's own history from this point
  forward is the artefact that matters for a portfolio.


