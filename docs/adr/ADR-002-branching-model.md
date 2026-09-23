# ADR-002: Branching model and merge methods

## Status
Accepted — 2026-09-23

## Context
Decision to implement branching discipline so as to be able to 
demonstrate release management maturiy.

## Decision
Long-lived integration branches: `develop`, `uat`, `main`, matching the
existing EAI deployment guide's promotion model. Feature branches are
named `feature/EPA-<n>-<short-description>` and are squash-merged into
`develop`. Promotion from `develop` to `main` (and, once a UAT-shaped
environment exists again, to `uat`) uses `--no-ff`, never a plain merge,
so that a promotion always creates its own commit and is never a silent
fast-forward (a fast-forward defeats the ECR/ACR immutable-tag
idempotency check).

## Consequences
- `git log --graph` on `main` shows a clean line of promotion commits,
  each traceable to the `develop` state it promoted.
- A feature branch's own internal commit noise (fixups, typo commits)
  never reaches `develop` — squash merging collapses it to one commit
  per story, matching one Jira ticket to one `develop` commit.
