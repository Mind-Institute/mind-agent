# Claude Code Project Rules

Before doing any work, read:
1. `README_FIRST.md`
2. `docs/00_EXECUTION_CONTROL.md`
3. `docs/00_ARCHITECTURE.md`

You are the technical executor of this project. Architecture is governed by the versioned project documents, not by convenience in the current task.

## Mandatory behavior

- Do not invent new schemas, tables, entities, runtimes or architectural patterns without checking the existing architecture first.
- Do not duplicate person, organization, product, product run or concept.
- Do not treat CRM contact as canonical person identity.
- Do not treat a product edition/cohort as a new canonical product.
- Do not expose arbitrary SQL as the main interface for LLM agents.
- Do not put commercial truth such as price, lot, availability or discount authority inside prompts.
- Do not silently turn AI inference into fact; persist source, confidence and provenance.
- Do not make production schema changes manually outside versioned migrations.
- Do not delete or destructively alter structures without checkpoint and rollback plan.
- Do not deploy or modify production unless the task explicitly authorizes it.
- Do not expose privileged secrets to browser/client code.
- Do not create a parallel conversation runtime when shared `engagement` should be used.
- Do not redesign the architecture while implementing a local feature.

## If a task conflicts with architecture

Stop before implementing the conflicting change.
Return:
1. the exact conflict;
2. why the current request would violate architecture;
3. the smallest viable options;
4. expected migration/compatibility impact.

Wait for approval before implementing an architectural deviation.

## Scope discipline

Implement only the requested step.
Do not opportunistically refactor unrelated parts of the repository.
Do not build future domains just because the schema allows them.

## Required quality for schema changes

Every structural database change should include, when applicable:
- declarative/current schema source;
- migration;
- rollback or reversibility note;
- tests/validation query;
- documentation update.

## Required quality for external actions

Writes to HubSpot, Treble, email, calendar or other external systems must be idempotent and auditable.

## Context philosophy

Agent runtime uses:
- minimal Base Context;
- Context Planner;
- just-in-time retrieval;
- deep memory/research only when necessary.

Do not solve missing context by loading entire datasets into prompts.

## Current execution state

Always defer to `docs/00_EXECUTION_CONTROL.md` for what is being done now and what is explicitly out of scope.