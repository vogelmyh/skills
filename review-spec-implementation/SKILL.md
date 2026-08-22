---
name: review-spec-implementation
description: >-
  Independently review a visible candidate against a frozen specification for
  compliance, correctness, minimality, risk, and evidence quality. Use when the
  user invokes this skill in a review context independent from incremental or
  greenfield implementation. Do not use to design, implement, or fix findings.
---

# Review Spec Implementation

Judge whether a candidate correctly and minimally satisfies a `FROZEN SPEC`,
independent of its design method. Own findings, evidence, status, and the review
artifact—not fixes.

## Inputs and Independence

Assume the user invoked this skill in a review context independent from
implementation. Do not create or delegate to another agent to establish that
boundary. Required inputs are:

- the frozen `SPEC.md`,
- the actual visible candidate and project workspace,
- the candidate baseline when one exists.

The candidate may be a diff, commit, branch, worktree, or greenfield tree.
This skill is self-contained. Follow project instructions if present and use
objective results when available.

If an objective implementation handoff is available, inspect its status. Only
`READY_FOR_REVIEW` is approvable; any explicit non-ready status requires
`REVIEW_BLOCKED`. If the user requests a partial assessment, add clearly marked
advisory findings while retaining `REVIEW_BLOCKED`. Absence of a handoff is not
itself a blocker when the actual candidate, baseline, and spec support an
independent judgment.

Before reading implementation rationale, independently answer:

```text
What does the spec require?
What does the candidate implement?
Which parts are necessary, sufficient, and correct?
```

If the spec, actual candidate, or required baseline cannot support a responsible
judgment, stop as `REVIEW_BLOCKED`. Do not guess.

## Hard Boundary

Do not intentionally modify tracked production source, fix findings, or broaden
the spec. Verification commands may create identifiable, safe-to-clean cache,
build, coverage, or temporary artifacts. Inspect status before and after; never
remove pre-existing or user-owned files, and report residue. Avoid commands that
rewrite source or lock files.

Route any required frozen-decision change to the user and spec owner; do not
prescribe new architecture.

## 1. Establish the Review Baseline

1. Read the complete spec and verify exactly one unambiguous `Status: FROZEN`
   plus the objective, non-goals, decisions and final design, invariants,
   implementation responsibilities, acceptance criteria, verification strategy,
   and known risks. Equivalent sections are allowed. Read project instructions,
   if any.
2. Resolve the exact candidate and baseline; inspect status so pre-existing work
   is not attributed to the candidate.
3. Map requirements, non-goals, decisions, invariants, acceptance criteria, and
   material risks to candidate responsibilities.

Inspect code, not only summaries: the diff and surrounding code for incremental
work, or the complete relevant tree and paths for greenfield.

## 2. Review Lanes

### Lane A: Specification compliance

Check requirements, acceptance criteria, non-goals, frozen decisions,
invariants, and applicable material interface, data, dependency, deployment,
migration, compatibility, and rollout effects. Find silent deviations.

### Lane B: Correctness and system risk

Trace relevant paths for boundary, state, persistence, recovery, concurrency,
trust, cleanup, configuration, and caller-compatibility failures.

Report only issues supported by a reproducible scenario, violated invariant,
or strong code evidence. Do not report an unrelated pre-existing defect, but do
report one that the candidate activates, makes reachable, or materially
amplifies.

### Lane C: Scope and minimality

Ask whether every candidate responsibility is necessary for the frozen spec.
Consider broad unrelated work, premature abstractions, speculative or duplicated
mechanisms, unjustified dependency/interface expansion, obscuring churn, and
total complexity.

Raise a scope finding only when the excess is material to behavior, maintenance,
risk, or reviewability. A harmless local helper or small implementation detail
is not a finding merely because another shape was possible. Minimality means
minimum sufficient system complexity, not minimum line count.

### Lane D: Verification quality

Check whether evidence supports criteria, invariants, and risk proportionately;
it increases confidence but does not prove correctness. Look for material
untested paths, bypassing mocks, trivia-coupled assertions, unrun checks, and
end-to-end or regression gaps.

Run focused verification when feasible. Record exact results. Do not convert an
infrastructure failure into a code finding without evidence.

## 3. Finding Standard

Findings are the primary output. Each actionable finding must contain:

```text
ID and severity:
Title:
Spec obligation or invariant:
Evidence: exact file and tight line/symbol location
Failure scenario or impact:
Required outcome, not a prescribed implementation:
Route: implementation or spec owner
```

Use severity consistently: `P0` catastrophic/system-wide release blocking;
`P1` high-impact correctness, security, data-loss, or core requirement failure;
`P2` real functional issue or material evidence gap under a plausible condition;
`P3` concrete non-blocking maintainability or scope note.

`P0`-`P2` findings are blocking. A `P3` is never sufficient by itself to request
changes and may coexist with `APPROVED`.

Do not report preferences, implausible possibilities, unrelated pre-existing
defects, or automated style differences. If no actionable finding exists, say
so; do not invent one.

## 4. Decide Review Status

Use one status:

- `APPROVED`: no blocking `P0`-`P2` finding remains and verification evidence is
  proportionate to risk; non-blocking `P3` notes may remain.
- `CHANGES_REQUESTED`: at least one blocking `P0`-`P2` implementation or spec
  finding remains.
- `REVIEW_BLOCKED`: missing spec, candidate, required baseline, environment, or
  evidence prevents a responsible judgment.

A `P3` alone must not produce `CHANGES_REQUESTED`. An `APPROVED` status does not
claim exhaustive proof. State residual risk and unrun checks.

For high-risk boundaries, recommend separate black-box or adversarial checks
when needed.

## 5. Persist `REVIEW.md`

Write `REVIEW.md` beside the spec unless applicable project instructions define
another location:

```markdown
# <Specification> Implementation Review

Status: APPROVED | CHANGES_REQUESTED | REVIEW_BLOCKED
Spec: <path or identifier>
Candidate: <commit/diff/worktree/tree/snapshot>
Baseline: <commit/tree/snapshot or None>
Blocking condition: <required for REVIEW_BLOCKED; otherwise None>
Action needed: <required for REVIEW_BLOCKED; otherwise None>

## Findings

### R1 [P1] <Title>
- Spec/invariant:
- Evidence:
- Impact:
- Required outcome:
- Route: implementation | spec owner

## Verification performed

## Verification gaps

## Minimality assessment

## Residual risks
```

When there are no findings, omit the sample and write `None.` Keep evidence
concise and independently checkable.

If the spec path is missing, return the same `REVIEW_BLOCKED` fields inline,
including the blocking condition and action needed. If persistence alone is
impossible or unauthorized, return the otherwise valid status and complete
review inline, and note that `REVIEW.md` was not written; inability to persist an
artifact does not by itself block judgment. Do not invent an artifact location.

## 6. Handoff and Stop

Lead with status and findings ordered by severity. Then summarize verification,
minimality, and residual risk.

For `CHANGES_REQUESTED`, return all findings to the user with each route marked
as implementation or spec owner. Do not fix them here.

For `REVIEW_BLOCKED`, state the exact blocking condition and the smallest action
needed to resume. Non-blocking `P3` notes may be routed to the implementation
owner without withholding approval.

The user chooses whether later review reuses an existing review context or uses
another independent one. Any review context can take over from the complete
spec, candidate, baseline, and prior review artifact. A changed frozen contract
requires implementation, verification, and a new `READY_FOR_REVIEW` handoff
before review. Recheck the full relevant candidate, not only prior finding
locations, and update `REVIEW.md` when persistence is available.
