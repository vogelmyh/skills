---
name: implement-frozen-spec
description: >-
  Implement an approved frozen specification when the user invokes this skill
  in an implementation context separate from design, including focused
  verification, self-review, and scope minimization. Use when a `SPEC.md` is
  marked `Status: FROZEN` and the user has authorized implementation, whether
  the spec describes an incremental change, greenfield system, bug fix, or
  migration. Do not use to explore or redesign an unfrozen requirement, or to
  independently approve the resulting implementation.
---

# Implement Frozen Spec

Implement only the frozen contract and produce a verified candidate. This
skill is self-contained and uses the spec, workspace, implementation
authorization, and any project instructions that exist. This stage owns
implementation and author self-review, not design exploration or independent
review.

## Required Inputs and Context Boundary

Assume the user invoked this skill in an implementation context separate from
design. Do not create or delegate to another agent to establish that boundary.
Required inputs are:

- the frozen `SPEC.md`,
- the project workspace,
- explicit user authorization to implement the spec.

Follow applicable project instructions when present; none are required by this
skill. Do not depend on the upstream design conversation. Read optional
evidence only when referenced by the spec or needed to verify a project claim.

## Frozen Spec Gate

Before modifying code, evaluate the spec before authorization:

1. locate and read the complete `SPEC.md`,
2. confirm it contains exactly one unambiguous `Status: FROZEN`,
3. confirm it provides the consumable core interface described below,
4. read applicable project instructions, if present,
5. inspect repository or workspace status and preserve user-owned changes,
6. verify current-state claims where the spec describes an existing system,
7. map every acceptance criterion to an implementation or verification step,
8. after the spec is consumable, confirm the user has explicitly authorized
   implementation.

A consumable spec must define, directly or through equivalent sections:

- objective or requirement,
- non-goals,
- frozen decisions,
- final design,
- constraints and invariants,
- expected implementation responsibilities,
- acceptance criteria,
- verification strategy,
- known risks.

Current behavior, compatibility, migration, platform, deployment, and
operational sections are conditional; do not require irrelevant ones.

If the spec is missing, unfrozen, internally contradictory, materially
invalidated by project evidence, or omits a decision needed to define the
architecture or acceptance criteria, stop with:

```text
Implementation status: SPEC_BLOCKED
Spec:
Conflict or missing decision:
Evidence:
Decision needed:
Return to: user and upstream spec owner
```

Do not repair upstream architecture decisions inside the implementation stage.
This entry-gate status takes precedence over authorization: first establish a
consumable frozen spec, then check permission to implement it.

If the spec is consumable but authorization is missing, do not modify code and
stop with:

```text
Implementation status: AUTHORIZATION_REQUIRED
Spec: <path>
Authorization needed: explicit permission to implement the frozen spec
Next stage: resume implementation after authorization.
```

## Plan and Implement Within the Frozen Boundary

Plan concise, verifiable increments mapped to frozen responsibilities and
acceptance criteria; do not recreate the architecture plan. Use applicable
project conventions and the minimum sufficient complexity. Keep code and tests
in scope, avoid unrelated churn or speculative generalization, and make
reviewable changes. Preserve behavior outside the spec in existing systems;
for greenfield work, add only foundations the spec requires.

Decide details autonomously within the contract. Material elements explicitly
required or authorized by the spec—including dependencies, interfaces, data
models, component boundaries, and deployment changes—do not require renewed
approval. Escalate only when evidence requires adding, removing, or materially
changing a frozen decision, invariant, responsibility, compatibility or
rollout promise, or acceptance criterion.

## Handle New Evidence Without Silent Deviation

If implementation reveals that the frozen design cannot be implemented as
written, do not silently deviate.

For a material conflict or scope expansion, stop with:

```text
Implementation status: SPEC_REOPEN_REQUIRED
Spec: <path>
Frozen decision affected:
Project evidence:
Smallest viable alternatives:
Scope effect:
Decision needed:
Candidate: <exact commit/diff/worktree/tree/snapshot and short summary or none>
Baseline: <commit/tree/snapshot or none>
Verification run: <commands/checks and results or none>
Return to: user and upstream spec owner
```

Use `SPEC_REOPEN_REQUIRED` only after a spec passed the entry gate and later
implementation evidence conflicts with it. Resume only after the spec is revised
and frozen again; then re-enter the complete Frozen Spec Gate, remap all
acceptance criteria, and obtain renewed authorization if the revised contract
materially exceeds the authorization already given.

For a minor ambiguity with one clearly conventional and scope-neutral answer,
choose it, record the assumption in the handoff, and continue.

## Verify and Minimize the Candidate

Add or update checks that provide proportionate evidence for acceptance criteria
and relevant failure, boundary, integration, recovery, compatibility, and
operational behavior. Run focused checks first, then the smallest relevant
regression set.

Do not claim unrun checks. If an intended check cannot run, record why and the
resulting risk. An unrun non-essential check may remain a known gap only when
its absence does not prevent a responsible independent review. A failed or
unrun essential check is a blocker, not a ready-state caveat.

Then perform an author's subtractive pass over the complete candidate. Remove
speculative abstractions, duplicated paths, unrelated churn, restatement
comments, trivia-coupled tests, and unnecessary scaffolding. Every changed file
must map to a frozen requirement, constraint, invariant, or verification need.
Remove unmapped candidate work without disturbing existing user work, inspect
the final candidate, and rerun affected checks.

## Outcome Gate and Handoff

If authorization, the spec gate, or new evidence stops work, use
`AUTHORIZATION_REQUIRED`, `SPEC_BLOCKED`, or `SPEC_REOPEN_REQUIRED` as defined
above. Otherwise finish with exactly one of the mutually exclusive outcomes
`READY_FOR_REVIEW` or `IMPLEMENTATION_BLOCKED`.

Use `READY_FOR_REVIEW` only when every frozen requirement is implemented, no
known silent deviation remains, all essential focused checks pass, applicable
regression checks have run or any non-essential omission is justified, the
subtractive pass is complete, and the candidate is independently reviewable
from an exact candidate boundary and its baseline when one exists. Return:

```text
Implementation status: READY_FOR_REVIEW
Spec: <path>
Candidate: <exact commit/diff/worktree/tree or bounded workspace snapshot>
Baseline: <commit/tree/snapshot or none>
Implemented responsibilities: <short list>
Verification run: <commands/checks and results>
Unrun checks or known gaps: <list or none>
Minor scope-neutral assumptions: <list or none>
Next stage: return control to the user for independent review with
review-spec-implementation.
```

Use `IMPLEMENTATION_BLOCKED` when the contract remains valid but a requirement
is incomplete, an essential check fails or cannot run, or an environmental or
dependency blocker prevents responsible review. Return:

```text
Implementation status: IMPLEMENTATION_BLOCKED
Spec: <path>
Candidate: <exact commit/diff/worktree/tree/snapshot and short summary or none>
Baseline: <commit/tree/snapshot or none>
Blocker and evidence: <what prevents completion or essential verification>
Remaining requirements: <short list>
Verification run: <commands/checks and results>
Action needed: <smallest concrete unblock step>
Next stage: return control to the user; implementation must resume before
independent review.
```

Author self-review is not approval. Pass the reviewer only objective artifacts,
assumptions, gaps, and observed check results, then stop.

If review later requests implementation changes, return the findings and
handoff artifacts to the user. The user chooses whether to resume an existing
implementation context or invoke another one. Any implementation context can
resume from the spec, exact candidate and baseline, verification record, and
review findings. Spec defects return to the user and upstream spec owner.
