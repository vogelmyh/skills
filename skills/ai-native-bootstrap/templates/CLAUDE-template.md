# CLAUDE.md

<!-- Project constitution. Claude Code reads this file automatically in every session.
     Keep it short and factual: every line costs context. Delete sections that don't apply. -->

## Project Overview

[One paragraph: what this project is, who it serves, and its current stage (prototype / production / migration).]

## Tech Stack

- **Language**: [e.g. TypeScript 5.x on Node 20]
- **Framework**: [e.g. Next.js 15, FastAPI]
- **Storage**: [e.g. PostgreSQL via Prisma; N/A]
- **Package manager**: [e.g. pnpm — do not use npm/yarn]

## Commands

<!-- The agent uses these to self-test and self-debug. They must actually work. -->

```bash
[install command]        # install dependencies
[build command]          # build
[test command]           # run all tests
[single-test command]    # run a single test file (agent prefers this while iterating)
[lint command]           # lint + format check
[dev command]            # start dev server / run locally
```

## Project Structure

```text
[Top-level directory tree with a one-phrase responsibility per directory, e.g.
src/
├── api/        # HTTP route handlers, no business logic
├── services/   # business logic, one service per domain
└── models/     # persistence models]
```

## Code Style & Conventions

- [Naming, file organization, import rules — only the ones not enforced by the linter]
- [Error-handling convention, e.g. "services throw typed errors; handlers translate to HTTP codes"]
- [Comment/documentation expectations]

## Testing

- [Framework and where tests live, e.g. "vitest; tests co-located as *.test.ts"]
- [What must be tested, e.g. "every service function needs unit tests; API changes need integration tests"]
- Definition of done for any task: build passes, lint passes, tests pass.

## Constraints (Do NOT)

<!-- Hard rules. For existing codebases, include architecture that must not be changed. -->

- [e.g. Do not modify files under src/legacy/ — scheduled for removal]
- [e.g. Do not add new runtime dependencies without asking]
- [e.g. Do not change the public API contract in api/v1]

## Learnings / Gotchas

<!-- Living section, appended by the agent during implementation: environment traps,
     non-obvious dependency behavior, debugging conclusions worth remembering.
     One bullet per learning — keep only facts that will save future work. -->

- [e.g. vitest requires NODE_OPTIONS=--experimental-vm-modules for ESM mocks]
- [e.g. the staging DB rejects connections without sslmode=require]

## Spec-Driven Workflow

Feature work is driven by documents in `specs/{feature}/`:

- `requirements.md` — what to build (user stories, acceptance criteria)
- `design.md` — how to build it (architecture, components, data models)
- `tasks.md` — ordered atomic task checklist

When implementing:

- Work with an existing `tasks.md` directly in agent mode — the specs are the approved plan, so do not re-plan tasks that are already atomic in `tasks.md`.
- Follow `tasks.md` top to bottom; mark tasks `- [x]` when their acceptance criteria pass.
- If implementation reveals a spec document is wrong, update the document — do not silently diverge from it.
- After completing a task or solving a non-trivial bug, write any reusable insight (pitfall, hidden constraint, debugging conclusion) into the Learnings / Gotchas section above, and correct any convention elsewhere in this file that the work disproved.
