# Tasks: [FEATURE NAME]

**Status**: Draft | In Progress | Done
**Design**: [design.md](design.md)

## Task Rules

Every task must be atomic so an agent can execute it in one focused pass:

- Touches 1–3 related files, listed by exact path
- One testable outcome; completable in 15–30 minutes
- Traces to requirements via `_Requirements: X.Y_`; builds on existing code via `_Leverage: path_`
- `[P]` marks tasks that can run in parallel with other `[P]` tasks in the same phase (different files, no dependency)
- Avoid vague titles ("implement system", "complete integration") — name the concrete artifact

## Phase 1: Setup

<!-- GREENFIELD: scaffolding, dependency manifest, lint/test tooling.
     EXISTING CODEBASE: usually minimal — new dependencies, config, migrations. Delete if empty. -->

- [ ] 1. [Create project skeleton / add dependency / write migration] in [exact path]
  - [implementation detail]
  - _Requirements: [X.Y]_

## Phase 2: Core

<!-- Foundational work that later tasks depend on: models, shared utilities, interfaces. -->

- [ ] 2. [P] Create [entity] model in [src/models/entity.ts]
  - [fields, validation]
  - _Requirements: [X.Y]_
- [ ] 3. Implement [service] in [src/services/service.ts]
  - [key logic; error handling per design.md]
  - _Leverage: [existing path]_
  - _Requirements: [X.Y]_
- [ ] 4. [P] Unit tests for [service] in [tests/services/service.test.ts]
  - [cases: happy path, edge cases from requirements.md]
  - _Requirements: [X.Y]_

## Phase 3: Feature

<!-- User-facing behavior: endpoints, UI, wiring. Repeat the pattern per component from design.md. -->

- [ ] 5. Implement [endpoint/component] in [exact path]
  - [request/response contract or props per design.md]
  - _Leverage: [existing path]_
  - _Requirements: [X.Y]_
- [ ] 6. Integration test for [flow] in [tests/integration/flow.test.ts]
  - [scenario mapped to acceptance criteria]
  - _Requirements: [X.Y]_

## Phase 4: Polish

- [ ] 7. Update documentation ([README / docs path]) for the new feature
  - _Requirements: [X.Y]_
- [ ] 8. Run full build, lint, and test suite; fix any failures
- [ ] 9. Write back learnings and spec corrections
  - Append pitfalls, hidden constraints, and debugging conclusions discovered during implementation to the Learnings / Gotchas section of [AGENT INSTRUCTIONS FILE]
  - Fix any conventions in [AGENT INSTRUCTIONS FILE] that this work disproved
  - Update design.md where the actual implementation diverged from it

## Requirements Coverage

<!-- Every requirement from requirements.md must appear here. Fill before approval. -->

| Requirement | Covered by tasks |
|-------------|------------------|
| 1 | [task numbers] |
| 2 | [task numbers] |
