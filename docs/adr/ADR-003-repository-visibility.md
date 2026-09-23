# ADR-003: Repository visibility

## Status
Accepted — 2026-09-21 (decision made); recorded — 2026-09-23

## Context
Private repositories on a free personal GitHub plan restrict several 
features this plan depends on (branch protection rules on private repos, 
some Actions minutes behaviour) more tightly than public repositories do, 
and a portfolio artefact intended to be shown to a someone wanting to 
see the repos is of limited use if it cannot actually be opened by them.

## Decision
POC repositories are published as **public**, after the scrub has run
and passed. Nothing is made public before the scrub gate closes.

## Consequences
- The scrub is a hard publication gate, not a courtesy step —
  this ADR is the record of why the gate exists in the first place.
- Branch protection and required status checks are available without a
  paid plan.
- Real identifiers and secrets must never reach a commit on this
  repository, at any point, including after publication — there is no
  "private for now, made public later" safety margin.
