# Requirements: [FEATURE NAME]

**Status**: Draft | Approved
**Source**: [PRD path/link, or "interview on YYYY-MM-DD"]

## Introduction

[2–4 sentences: what this feature is, the problem it solves, and its value to users.]

## Requirements

<!-- One block per requirement. Number them (1, 2, 3…) — tasks.md traces back to these numbers.
     Acceptance criteria use EARS format: WHEN/IF <trigger> THEN <system> SHALL <response>.
     For changes to existing behavior, state the delta: "currently does X; SHALL do Y". -->

### Requirement 1: [Short Title]

**User Story:** As a [role], I want [capability], so that [benefit].

#### Acceptance Criteria

1. WHEN [event] THEN [system] SHALL [response]
2. IF [precondition] THEN [system] SHALL [response]
3. WHEN [event] AND [condition] THEN [system] SHALL [response]

### Requirement 2: [Short Title]

**User Story:** As a [role], I want [capability], so that [benefit].

#### Acceptance Criteria

1. WHEN [event] THEN [system] SHALL [response]

## Edge Cases

- WHEN [boundary condition, e.g. empty input / concurrent access / upstream timeout] THEN [system] SHALL [behavior]

## Non-Functional Requirements

<!-- Delete rows that don't apply; keep the ones with real, checkable targets. -->

- **Performance**: [e.g. p95 latency < 200ms at 100 concurrent users]
- **Security**: [e.g. all endpoints require auth; PII encrypted at rest]
- **Reliability**: [e.g. failed jobs retried 3 times, then dead-lettered]
- **Compatibility**: [e.g. existing API v1 clients must keep working]

## Non-Goals

<!-- Explicit scope boundaries — the agent must not build these. -->

- [Out-of-scope item and, if useful, why]

## Open Questions

<!-- Unresolved [NEEDS CLARIFICATION] items. Must be empty before approval. -->

- [NEEDS CLARIFICATION: question]
