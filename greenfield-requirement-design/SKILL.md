---
name: greenfield-requirement-design
description: >-
  Design a non-trivial greenfield product, service, component, or capability
  through targeted requirement reconnaissance and decision-focused
  collaboration, ending in a frozen implementation specification. Use only
  when the user explicitly invokes `$greenfield-requirement-design`. Do not use
  for incremental changes to an existing system, trivial work, or
  implementation of an already-frozen spec.
---

# Greenfield Requirement Design

Turn a greenfield requirement into an evidence-backed `FROZEN SPEC` without
writing production code. The spec is the complete interface to downstream
implementation and review; those stages need no design-conversation context.

## Hard Boundary

This skill ends at design freeze.

Do not create or modify candidate production source, create implementation
commits, perform implementation disguised as a prototype, continue into
implementation in this agent, or produce a detailed implementation plan before
freeze.

Safe research, diagnostic, or feasibility experiments may create disposable
artifacts. They must not become part of the candidate implementation or silently
decide a material product or architecture question.

## Inputs

Obtain the requirement, user or problem context, relevant documentation, stated
product and technical constraints, target platform or operating environment,
and applicable project instructions, if present.

If the requirement is fuzzy, begin with the smallest useful requirement
reconnaissance rather than asking the user to supply technical details they may
not know.

## 1. Establish Design and Artifact Constraints

Before design work, read applicable project instructions if present; identify
the authoritative requirement and constraint sources; inspect workspace status
without altering user-owned work when an existing workspace will hold the
design artifact; and locate any project-prescribed design artifact directory.

Do not inspect pre-existing product source, tests, control flow, data flow, or
similar implementations to reconstruct behavior or choose a design. If the
requirement materially depends on preserving or integrating with an existing
implementation, stop and route it to `incremental-change-design`.

Do not describe the whole product or problem domain to the user.

## 2. Targeted Requirement Reconnaissance

Investigate only what can affect the design. Establish:

- intended users, outcomes, and critical success and failure scenarios,
- system boundary, external actors, integrations, and trust boundaries,
- domain entities, state, lifecycle, and material invariants,
- product, platform, delivery, security, compliance, and operational constraints,
- assumptions or unknowns that could alter architecture, scope, risk, or
  verification.

Use requirement documents, user statements, applicable standards, target
platform documentation, and bounded feasibility evidence. Do not build a
solution merely to discover what the requirement should be.

Stop when additional research no longer changes a design decision, risk
assessment, acceptance criterion, or verification strategy.

Default to a compact L0 brief, often roughly 10-20 lines; vary the length when
the material findings warrant it:

```text
Requirement:
Users and critical scenarios:
System boundary:
Material constraints:
Key assumptions or unknowns:
Likely implementation responsibilities:
Next decision:
```

Distinguish sourced facts, approved choices, assumptions, and unresolved
unknowns. Keep detailed evidence internally or in optional adjacent
`EVIDENCE.md`; show it when useful, requested, or a claim is contested.

## 3. Discover Decisions

Ask for human judgment only when alternatives differ materially in:

- externally visible behavior or scope,
- architecture, component responsibilities, or ownership boundaries,
- data model, persistence, initialization, or retention,
- public interfaces, integrations, or trust boundaries,
- delivery, deployment, rollout, or operational model,
- security, privacy, compliance, or failure risk,
- long-term complexity, cost, reversibility, or extensibility.

Resolve low-risk details through approved constraints and established standards
of the selected platform.

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
Scope and responsibility effect:
```

Recommend an option and persist the result:

```text
D<n> <title>
Decision: <chosen outcome>
Reason: <short rationale>
Evidence: <optional requirement, constraint, or research source>
```

Do not reopen a closed decision merely because another implementation is
available. Reopen it only when new evidence materially changes the approved
behavior, boundary, or risk. Explain the conflict and ask whether to revise the
decision.

## 5. Produce the Minimum Design and Escalate Scope

Choose the smallest design that fully meets the requirement. Prefer:

- the fewest necessary responsibilities and components,
- narrow public interfaces and trust boundaries,
- minimal external dependencies and persistent state,
- direct support for required scenarios over speculative flexibility,
- reversible choices and the simplest sufficient delivery model.

Fewest components is not the goal when collapsing responsibilities would
increase coupling, operational risk, or violate a real boundary.

Do not introduce a general-purpose platform, extension mechanism,
multi-implementation abstraction, or future-facing capability without a current
requirement or invariant.

Before adopting a material expansion—such as shared infrastructure, a new
dependency, persistent schema, public API, cross-component responsibility,
additional runtime or deployment unit, security boundary, or substantial
operational burden—stop for the user's decision:

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

- Can an abstraction, dependency, option, component, or layer be removed?
- Can the required behavior use one simpler responsibility or path?
- Is any capability speculative or outside the requirement?
- Can the interface, trust, state, deployment, or operational surface be smaller?
- Does each proposed responsibility support a requirement or invariant?

Record material removals or why apparently removable complexity is necessary.

For several subsystems, persistent schemas, new dependencies, security
boundaries, multiple deployment units, or multiple new abstractions, recommend
an independent design critic when available and authorized.

## 7. Freeze the Shared Specification Interface

Freeze only when:

- the requirement, intended users, critical scenarios, and non-goals are explicit,
- system boundaries, material constraints, and assumptions are validated or
  explicitly accepted,
- material decisions are closed and the complexity challenge is complete,
- implementation responsibilities, interfaces, data, dependencies, delivery or
  operational effects, acceptance criteria, and verification strategy are
  explicit and testable,
- no blocking design question remains.

Write `SPEC.md` to the location required by applicable project instructions.
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

Add sections such as `System context and assumptions`, `Interfaces and data
model`, or `Deployment, bootstrap, and rollback` only when they carry material
information not expressed clearly in the shared core.

Headings may follow project conventions, but all core information must remain
unambiguous.

The frozen spec must be:

- self-contained without design-conversation access and concise enough to act
  as an interface rather than a research report,
- specific about behavior and invariants but not prescriptive about harmless
  local implementation details,
- explicit about material component boundaries, interfaces, schema,
  dependencies, security, delivery, and operational responsibilities,
- clear about which statements are facts, frozen decisions, or accepted
  assumptions,
- free of unresolved alternatives disguised as prose.

Put noisy evidence in adjacent `EVIDENCE.md`, but keep every frozen decision in
the spec; implementation must not require the evidence file.

## 8. Handoff and Stop

Return a compressed summary:

```text
Design frozen: <path to SPEC.md>
Final design: <2-4 bullets>
Implementation surface: <components/interfaces/data/dependencies/deployment>
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
