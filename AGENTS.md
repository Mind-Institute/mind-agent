# Coding Agent Instructions

Read these files before making changes:
- `README_FIRST.md`
- `docs/00_EXECUTION_CONTROL.md`
- `docs/00_ARCHITECTURE.md`

Treat them as project-level instructions.

## Operating model

Coding agents execute tasks. They do not own architecture or behavior definitions.

If a requested implementation appears to require a new entity, schema, agent runtime, data source of truth, behavior contract or architectural pattern not already defined:
- stop;
- explain the conflict;
- propose options;
- do not implement the architectural change without approval.

## Non-negotiable constraints

- No duplicate canonical entities.
- Person identity is distinct from CRM relationship.
- Human contact points are distinct from provider external refs.
- Product identity is distinct from product run/edition/cohort.
- Agents use semantic Agent API contracts, not arbitrary SQL as their primary interface.
- AI-derived data must preserve source, confidence and provenance.
- `intelligence.facts` must not become a duplicate of canonical domains.
- Commercial truth must come from commercial data, not prompts or generic RAG.
- Structured authoritative truth beats stale/unstructured semantic retrieval.
- Structural database changes are versioned and tested.
- Destructive work requires checkpoint and rollback/recovery plan.
- Production is not a development environment.
- External writes must be idempotent and auditable.
- Context should be minimal by default and retrieved just-in-time.
- Shared engagement does not mean one infinite cross-channel conversation.
- Outbound requires deterministic contactability/consent/suppression checks.
- Agent behavior changes require relevant eval/regression checks.
- Do not store chain-of-thought; store operational decisions, versions and retrieval/context trace.

## Domain-specific reading

For Sales behavior/prompt/playbook/model work:
- `docs/11_SALES_AGENT_BEHAVIOR_SPEC.md`
- `docs/13_EVALS_AND_OBSERVABILITY.md`
- `docs/03_AGENT_RUNTIME_CONTEXT_MEMORY.md`

For knowledge/RAG/site ingestion:
- `docs/12_KNOWLEDGE_INGESTION_AND_RETRIEVAL.md`

For outbound:
- `docs/14_OUTBOUND_WORKFLOW.md`
- privacy/contactability sections of `docs/02_TARGET_DATA_MODEL.md`

For database/source-of-truth/migration:
- `docs/02_TARGET_DATA_MODEL.md`
- `docs/09_SOURCE_OF_TRUTH_DRAFT.md`
- `docs/06_SECURITY_AND_CHANGE_PROTOCOL.md`
- current-to-target/migration plan once created.

## Vibe Code discipline

Before coding:
1. identify the active phase in `00_EXECUTION_CONTROL.md`;
2. identify the relevant normative spec;
3. identify acceptance/eval cases;
4. implement only the requested step;
5. run the applicable checks;
6. report architectural conflict instead of improvising a parallel solution.

## Current state

For the active objective, current phase, checkpoint gaps, done criteria and forbidden work, always read `docs/00_EXECUTION_CONTROL.md` immediately before implementation.