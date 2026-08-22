# Coding Agent Instructions

Read these files before making changes:
- `README_FIRST.md`
- `docs/00_EXECUTION_CONTROL.md`
- `docs/00_ARCHITECTURE.md`

Treat them as project-level instructions.

## Operating model

Coding agents execute tasks. They do not own architecture.

If a requested implementation appears to require a new entity, schema, agent runtime, data source of truth, or architectural pattern not already defined:
- stop;
- explain the conflict;
- propose options;
- do not implement the architectural change without approval.

## Non-negotiable constraints

- No duplicate canonical entities.
- Person identity is distinct from CRM relationship.
- Product identity is distinct from product run/edition/cohort.
- Agents use semantic Agent API contracts, not arbitrary SQL as their primary interface.
- AI-derived data must preserve source, confidence and provenance.
- Commercial truth must come from commercial data, not prompts.
- Structural database changes are versioned and tested.
- Destructive work requires checkpoint and rollback plan.
- Production is not a development environment.
- External writes must be idempotent and auditable.
- Context should be minimal by default and retrieved just-in-time.
- Do not create parallel conversation/memory systems for different channels.

## Current state

For the active objective, current phase, done criteria and forbidden work, always read `docs/00_EXECUTION_CONTROL.md` immediately before implementation.