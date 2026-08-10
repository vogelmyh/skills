---
name: ai-native-bootstrap
description: Bootstrap AI Native, spec-driven development for a project by interviewing the user and generating CLAUDE.md, requirements.md, design.md, and tasks.md from industry-standard templates. Use when the user wants to set up AI Native coding, initialize spec-driven development, create or restructure CLAUDE.md, turn a PRD into specs, or asks to 梳理项目约束 / 生成开发规范文档 / AI 原生开发 for Claude Code agent mode.
---

# AI Native Bootstrap

Guide the user through structured interviews to produce the four documents that let a coding agent work autonomously (implement, self-test, self-debug, generate docs):

| Document | Location | Role |
|----------|----------|------|
| `CLAUDE.md` | repository root | Project constitution: constraints, commands, conventions the agent must always follow |
| `requirements.md` | `specs/{feature}/` | What to build: user stories + EARS acceptance criteria |
| `design.md` | `specs/{feature}/` | How to build it: architecture, components, data models |
| `tasks.md` | `specs/{feature}/` | Ordered atomic tasks with requirement traceability |

Each document is generated from a template in `templates/`. Read the template only when you reach the corresponding phase.

## Core Rules

1. **Extract, then confirm — never re-ask.** Anything that can be extracted from a PRD or inferred from the codebase must not be asked as an open question. Present extracted/inferred content as a draft and ask the user to confirm or correct it.
2. **Approval gates.** After generating each document, show a summary and wait for explicit user approval before starting the next phase. Incorporate feedback by editing the document, not by regenerating from scratch.
3. **Interview etiquette.** Ask at most 3–5 questions per round. Every question must offer a sensible default or concrete options. Conduct the interview in the user's language; write the generated documents in the language used by the project (default: English, unless the user prefers otherwise).
4. **One feature per spec.** If the user describes multiple independent features, help them pick one to spec first; create separate `specs/{feature}/` directories for the rest later.

## Phase 0: Scenario Routing

Before anything else, determine the scenario with two questions (skip a question if the answer is already obvious from context):

1. **Is there a PRD** (or any requirements document, design doc, issue thread)? If yes, ask for the file path or pasted content.
2. **Greenfield or existing codebase?** If existing, confirm the repository root.

The answers select the information source for each later phase:

| Scenario | Requirements source | Technical constraints source |
|----------|--------------------|------------------------------|
| PRD + greenfield | Parse PRD; ask only about gaps | Interview (tech stack, style preferences) |
| PRD + existing code | Parse PRD; ask only about gaps | Scan codebase, confirm inferences |
| No PRD + greenfield | Full requirements interview | Interview |
| No PRD + existing code | Interview, anchored on current codebase state | Scan codebase, confirm inferences |

**Codebase scan** (existing-code scenarios): before asking the user anything technical, read the README, package/build manifests (`package.json`, `pyproject.toml`, `go.mod`, etc.), CI config, lint/format config, and the top 2 levels of the directory tree. Record inferred build/test/lint commands, tech stack, and structure conventions as drafts for Phase 1.

**PRD parsing** (PRD scenarios): read the PRD fully. Extract user stories, acceptance criteria, and non-functional requirements. Mark every ambiguity or gap inline as `[NEEDS CLARIFICATION: question]`, then ask all clarification questions in one consolidated round.

## Phase 1: Project Constraints → CLAUDE.md

Read [templates/CLAUDE-template.md](templates/CLAUDE-template.md).

- **Greenfield**: interview to settle — tech stack and versions, package manager, build/test/lint commands (to be created), directory layout, code style, testing expectations, hard "do not" constraints.
- **Existing code**: fill the template from the Phase 0 scan, then present the draft for confirmation. Additionally ask: "Which parts of the current architecture must not be changed?" and record answers under Constraints.
- If a `CLAUDE.md` already exists, merge into it — preserve user content, add missing sections.

Write `CLAUDE.md` at the repository root. Gate: user approval.

## Phase 2: Requirements → specs/{feature}/requirements.md

Read [templates/requirements-template.md](templates/requirements-template.md). Agree on a short kebab-case feature name for the `specs/{feature}/` directory.

- **With PRD**: the PRD is the single source of truth. Transcribe it into the template (user stories, EARS-format acceptance criteria). Resolve `[NEEDS CLARIFICATION]` markers with the user in one round; do not invent requirements the PRD doesn't support.
- **Without PRD, greenfield**: interview by topic — target users and their goals; core user journeys (walk through the happy path step by step); edge cases and failure behavior; non-functional needs (performance, security, scale); explicit non-goals.
- **Without PRD, existing code**: first summarize the relevant current behavior of the codebase, then ask what should change relative to it. Frame requirements as deltas ("system currently does X; it SHALL do Y").

Gate: user approval.

## Phase 3: Design → specs/{feature}/design.md

Read [templates/design-template.md](templates/design-template.md).

- Propose an architecture that satisfies requirements.md within CLAUDE.md constraints. Where real trade-offs exist (storage choice, sync vs async, library selection), present 2–3 options with a recommendation instead of deciding silently.
- **Existing code**: the Code Reuse Analysis section is mandatory — identify concrete existing components to leverage and integration points, citing real file paths. Verify cited paths exist.
- **Greenfield**: replace Code Reuse Analysis with the Project Structure Plan section (directory tree to be created).
- Include a mermaid diagram for component relationships and data flow.

Gate: user approval.

## Phase 4: Task Breakdown → specs/{feature}/tasks.md

Read [templates/tasks-template.md](templates/tasks-template.md).

- Derive tasks from design.md. Every task must be atomic: 1–3 files, single testable outcome, exact file paths, completable in 15–30 minutes.
- Trace every task to requirements with `_Requirements: X.Y_`. Every requirement must be covered by at least one task.
- **Existing code**: add `_Leverage: path/to/existing/file_` to tasks that build on existing code.
- **Greenfield**: start with a Setup phase (scaffolding, dependency manifest, lint/test tooling) before feature tasks.
- Order tasks by dependency; mark independent tasks `[P]` (parallelizable).

Gate: user approval.

## Completion

After all four documents are approved:

1. Verify cross-consistency: every requirement is covered by tasks; design references no requirement that doesn't exist; commands in CLAUDE.md are runnable (existing code) or created by a Setup task (greenfield).
2. Tell the user how to proceed: work through `tasks.md` top to bottom in Claude Code agent mode, checking off tasks (`- [x]`) as they complete, and keeping CLAUDE.md/specs updated when reality diverges.
