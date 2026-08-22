---
name: incremental-change-design
description: >-
  Design a non-trivial incremental change in an unfamiliar existing codebase
  through targeted reconnaissance and decision-focused collaboration, ending
  in a frozen implementation specification. Use before implementation when the
  user needs to understand and approve a change to an existing system. Do not
  use for trivial edits, obvious bug fixes, greenfield architecture, or
  implementation of an already-frozen spec.
---

# Incremental Change Design

Turn an incremental requirement into an evidence-backed `FROZEN SPEC` without
writing production code. The spec is the complete interface to downstream
implementation and review; those stages need no design-conversation context.

## Hard Boundary

This skill ends at design freeze.

Do not edit tracked production source, create implementation commits, perform
implementation disguised as a prototype, continue into implementation in this
agent, or produce a detailed implementation plan before freeze.

Safe diagnostic or feasibility experiments may run builds or tests and create
disposable artifacts. They must not modify tracked production source or become
part of the candidate implementation.

## Inputs

Obtain the requirement, repository, relevant documentation, stated constraints,
and applicable project instructions, if present.

If the requirement is fuzzy, begin with the smallest useful reconnaissance
rather than asking the user to explain repository details they do not know.

## 1. Establish Repository Constraints

Before design work, read applicable project instructions if present; inspect
repository status and existing local changes without altering them; identify
likely build and test entry points; and locate any project-prescribed design
artifact directory.

Do not describe the whole repository to the user.

## 2. Targeted Reconnaissance

Investigate only what can affect the design. Trace:

- current behavior, ownership, and relevant control or data flow,
- similar mechanisms and conventions worth reusing,
- tests encoding current expectations,
- likely change boundaries and compatibility constraints.

Search outward from the requirement. Stop when additional files no longer
change a design decision, risk assessment, or verification strategy.

Default to a compact L0 brief, often roughly 10-20 lines; vary the length when
the material findings warrant it:

```text
Current behavior:
Relevant flow:
Likely change surface:
Existing mechanism to reuse:
Material unknowns:
Next decision:
```

Keep detailed citations internally or in optional adjacent `EVIDENCE.md`; show
them when useful, requested, or a claim is contested.

## 3. Discover Decisions

Ask for human judgment only when alternatives differ materially in:

- externally visible behavior,
- architecture or ownership boundary,
- data model or migration,
- compatibility or rollout,
- operational or security risk,
- long-term complexity, scope, cost, or reversibility.

Resolve low-risk details through project conventions.

Default to showing no more than five open decisions at once; group or sequence
more when useful.

## 4. Run the Decision Loop

Discuss one decision at a time by default. Handle tightly coupled decisions
together when separation would obscure the tradeoff:

```text
Decision:
Why it matters:
Option A:
Option B:
Recommendation:
Reason:
Change-surface effect:
```

Recommend an option and persist the result:

```text
D<n> <title>
Decision: <chosen outcome>
Reason: <short rationale>
Evidence: <optional repository locations>
```

Do not reopen a closed decision merely because another implementation is
available. Reopen it only when new evidence materially changes the approved
behavior, boundary, or risk. Explain the conflict and ask whether to revise
the decision.

## 5. Produce the Minimum Design and Escalate Scope

Choose the smallest design that fully meets the requirement. Prefer:

- existing module ownership,
- existing extension points and conventions,
- existing lifecycle and state models,
- backward-compatible defaults,
- local changes over new shared abstractions.

Fewest changed lines is not the goal when it increases system complexity or
violates a real boundary.

Before adopting a material expansion—such as a shared abstraction, dependency,
schema migration, public API change, cross-module ownership change, or broad
refactor—stop for the user's decision:

```text
Smallest current option:
Proposed expansion:
Why the smaller option fails:
Evidence:
User decision required:
```

Recommend broader scope only when evidence shows the smaller option is
inadequate.

## 6. Complexity Challenge

Before freeze, challenge the design:

- Can an abstraction, dependency, option, or layer be removed?
- Can an existing path be extended safely instead of creating a parallel path?
- Is any capability speculative or outside the requirement?
- Can the behavior have a smaller semantic blast radius?
- Does each changed responsibility support a requirement or invariant?

Record material removals or why apparently removable complexity is necessary.

For several subsystems, schema migration, new dependencies, security
boundaries, or multiple new abstractions, recommend an independent design
critic when available and authorized.

## 7. Freeze the Shared Specification Interface

Freeze only when:

- requirement and non-goals are explicit and current behavior is evidence-backed,
- material decisions are closed and the complexity challenge is complete,
- change surface, compatibility effects, acceptance criteria, and verification
  strategy are explicit and testable,
- no blocking design question remains.

Write `SPEC.md` to the location required by applicable repository instructions.
When none is defined, use `.codex/design/<feature>/SPEC.md`.

Place exactly one status near the top:

```text
Status: FROZEN
```

Include these shared core sections for generic downstream consumers:

```markdown
# <Feature> Specification

Status: FROZEN

## Objective

## Non-goals

## Decisions

## Final design

## Constraints and invariants

## Expected implementation responsibilities

## Acceptance criteria

## Verification strategy

## Known risks
```

Add these extensions for the existing system:

```markdown
## Current behavior

## Compatibility and change surface

## Migration and rollback
```

Use `none` when migration or rollback is inapplicable. Headings may follow
project conventions, but all core information must remain unambiguous.

The frozen spec must be:

- self-contained without design-conversation access and concise enough to act
  as an interface rather than a research report,
- specific about behavior and invariants but not prescriptive about harmless
  local implementation details,
- explicit about interfaces, schema, dependencies, affected behavior,
  migration, and rollback,
- free of unresolved alternatives disguised as prose.

Put noisy evidence in adjacent `EVIDENCE.md`, but keep every frozen decision in
the spec; implementation must not require the evidence file.

## 8. Handoff and Stop

Return a compressed summary:

```text
Design frozen: <path to SPEC.md>
Final design: <2-4 bullets>
Change surface: <modules/interfaces/schema/dependencies>
Main residual risk: <one item or none>
Production code changed: no
Next stage: return control to the user; they may invoke implement-frozen-spec in
a separate implementation context.
```

Do not paste the full spec unless requested. Do not start implementation or
create or delegate to another agent. The handoff for any later implementation
context consists of the frozen spec, project workspace, and explicit
implementation authorization; that context independently reads applicable
project instructions, if present.
