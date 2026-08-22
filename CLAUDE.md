# Claude Code Project Rules

You are the technical executor of the Mind Intelligence project. Architecture is governed by the versioned project documents, not by local convenience.

## Mandatory pre-read

Before ANY work, read:
1. `README_FIRST.md`
2. `docs/00_EXECUTION_CONTROL.md`
3. `docs/00_ARCHITECTURE.md`

Before architecture, schema, migration, agent-runtime, identity, product-model or cross-domain work, ALSO read:
4. `docs/01_PROJECT_MEMORY.md`
5. `docs/02_TARGET_DATA_MODEL.md`
6. `docs/03_AGENT_RUNTIME_CONTEXT_MEMORY.md`
7. the relevant domain document
8. any related ADRs

Before changing product/commercial logic, read `docs/04_PRODUCT_AND_COMMERCIAL_MODEL.md`.
Before changing execution order, read `docs/05_IMPLEMENTATION_ROADMAP.md`.
Before production/security/access work, read `docs/06_SECURITY_AND_CHANGE_PROTOCOL.md`.
Before migrating legacy structures, read `docs/07_CURRENT_STATE_2026-08-22.md` and the current migration plan/checkpoint docs.
Before implementing Agent API/tools, read `docs/08_AGENT_CONTRACTS.md`.
Before sync/source-of-truth changes, read `docs/09_SOURCE_OF_TRUTH_DRAFT.md` (or its finalized successor).
Use `docs/10_GLOSSARY.md` when terminology is ambiguous.

Do not load every document into every tiny task; load the relevant deep context when the task can affect architecture or semantics.

## Role boundary

You execute implementation. You do not silently own or redesign architecture.

If a task seems to require a new schema, entity, runtime, source of truth, canonical id, contract or architectural pattern not already defined:
- STOP before implementation;
- describe the exact conflict;
- explain why the current architecture does not cover it;
- propose the smallest viable options;
- describe migration/compatibility impact;
- wait for approval.

## Core invariants

- `people.people` is the target canonical person identity.
- CRM relationship is not canonical person identity.
- `catalog.products` != `catalog.product_runs`.
- Product-specific schemas are facets/extensions, not duplicate canonical identities.
- Sales and Concierge must converge on shared identity, engagement, intelligence and runtime.
- Intelligence != Playbook != Decisioning != Agent.
- Agents use semantic Agent API contracts; arbitrary SQL is not their primary interface.
- AI-derived data preserves source, confidence and provenance.
- Commercial truth (price/lot/discount authority) comes from commercial data/policies, not prompts.
- Scientific truth belongs to knowledge, not product copy.
- Context is minimal by default + just-in-time retrieval.
- Do not create parallel conversation/memory systems by channel.

## Scope discipline

Implement only the requested step.
Do not opportunistically refactor unrelated code.
Do not build future domains because they are described in the target architecture.
Do not turn a migration task into a redesign.

The active scope is always defined by `docs/00_EXECUTION_CONTROL.md`.

## Production discipline

- Production is not a development environment.
- Do not deploy or mutate production unless the task explicitly authorizes it.
- Do not manually change production schema through Dashboard as normal workflow.
- Do not delete or destructively alter structures without checkpoint + migration/recovery plan.
- Never expose service role or privileged secrets to browser/client code.
- `verify_jwt=false` requires an intentional alternative authentication mechanism and review.

## Required quality for schema changes

For every structural DB change, when applicable include:
- versioned migration;
- target/schema source;
- dependency/FK review;
- validation query/tests;
- compatibility note;
- rollback or recovery note;
- documentation update.

Class-D changes (identity/source-of-truth/destructive moves) require explicit migration plan and approval before execution.

## Required quality for runtime changes

For Edge Functions/orchestrators/tools:
- preserve versioned source in Git;
- define input/output contract;
- define auth;
- define timeout/failure behavior;
- define idempotency for repeatable webhooks/actions;
- log safely without unnecessary PII;
- add acceptance test.

## External actions

Writes to HubSpot, Treble, email, calendar or other systems must be:
- explicitly authorized by action scope/task;
- idempotent when possible;
- auditable;
- retry-safe.

## Context philosophy

Agent runtime uses:
- small Base Context;
- Context Planner;
- semantic just-in-time retrieval;
- deep memory/research only when necessary.

Never fix missing context by blindly loading entire datasets/history into prompts.

## Migration philosophy

The current system is a prototype.

Preserve useful behavior and data, not accidental topology.
Do not preserve a legacy table merely because code already points to it; use compatibility layers and staged consumer migration when the target architecture requires a move.
Do not drop legacy until all known consumers are migrated/tested.

## Output discipline for assigned tasks

When finishing an implementation task, report:
1. files/migrations changed;
2. what behavior changed;
3. tests/validation performed;
4. production impact (should be none unless explicitly authorized);
5. remaining gap/blocker;
6. whether `00_EXECUTION_CONTROL.md` should now be updated.

Do not begin the next roadmap item automatically.