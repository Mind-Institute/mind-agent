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
- Do not treat email/phone/contact points as the same thing as provider external ids.
- Do not treat a product edition/cohort as a new canonical product.
- Do not expose arbitrary SQL as the main interface for LLM agents.
- Do not put commercial truth such as price, lot, availability or discount authority inside prompts.
- Do not use embeddings/vector search as universal source of truth when structured authoritative data exists.
- Do not silently turn AI inference into fact; persist source, confidence and provenance.
- Do not copy canonical data into `intelligence.facts` merely for convenience.
- Do not make production schema changes manually outside versioned migrations.
- Do not delete or destructively alter structures without checkpoint and rollback/recovery plan.
- Do not deploy or modify production unless the task explicitly authorizes it.
- Do not expose privileged secrets to browser/client code.
- Do not create a parallel conversation runtime when shared `engagement` should be used.
- Do not assume shared engagement means one infinite conversation across every channel.
- Do not redesign the architecture while implementing a local feature.
- Do not ship an agent behavior change without the relevant eval/regression checks.
- Do not allow LLM decisions to override deterministic privacy/contactability/suppression rules.

## Read the domain-specific docs before implementation

### Database/entity/schema work
Read:
- `docs/02_TARGET_DATA_MODEL.md`
- `docs/09_SOURCE_OF_TRUTH_DRAFT.md`
- `docs/06_SECURITY_AND_CHANGE_PROTOCOL.md`
- future Current → Target / Migration Plan when present.

### Sales behavior/prompt/playbook/decisioning
Read:
- `docs/11_SALES_AGENT_BEHAVIOR_SPEC.md`
- `docs/03_AGENT_RUNTIME_CONTEXT_MEMORY.md`
- `docs/08_AGENT_CONTRACTS.md`
- `docs/13_EVALS_AND_OBSERVABILITY.md`

Behavior Spec is authoritative for what good Sales behavior means. Do not rewrite the behavior definition merely to fit an implementation.

### Knowledge/RAG/site ingestion/retrieval
Read:
- `docs/12_KNOWLEDGE_INGESTION_AND_RETRIEVAL.md`
- `docs/02_TARGET_DATA_MODEL.md`
- `docs/08_AGENT_CONTRACTS.md`
- `docs/13_EVALS_AND_OBSERVABILITY.md`

Do not solve all knowledge questions with generic vector retrieval.

### Outbound
Read:
- `docs/14_OUTBOUND_WORKFLOW.md`
- `docs/11_SALES_AGENT_BEHAVIOR_SPEC.md`
- privacy/contactability parts of `docs/02_TARGET_DATA_MODEL.md`
- `docs/13_EVALS_AND_OBSERVABILITY.md`

### Concierge
Read:
- `docs/03_AGENT_RUNTIME_CONTEXT_MEMORY.md`
- `docs/08_AGENT_CONTRACTS.md`
- `docs/13_EVALS_AND_OBSERVABILITY.md`
- Summit/product docs relevant to the task.

### Security/RLS/webhooks/external writes
Read:
- `docs/06_SECURITY_AND_CHANGE_PROTOCOL.md`
- `docs/09_SOURCE_OF_TRUTH_DRAFT.md`

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

`docs/00_EXECUTION_CONTROL.md` decides what is active now.

## Required quality for schema changes

Every structural database change should include, when applicable:
- declarative/current schema source;
- migration;
- rollback or reversibility/recovery note;
- tests/validation query;
- documentation update;
- dependency/consumer review for legacy objects.

## Required quality for agent-facing contract changes

When changing Agent API or structured output:
- update versioned contract/schema where applicable;
- inventory consumers;
- preserve compatibility or explicitly migrate;
- run contract tests;
- run relevant behavior evals.

## Required quality for external actions

Writes to HubSpot, Treble, email, calendar or other external systems must be idempotent and auditable.

Outbound additionally requires deterministic contactability/consent/suppression and cadence checks before send.

## Context philosophy

Agent runtime uses:
- minimal Base Context;
- Context Planner;
- just-in-time retrieval;
- deep memory/research only when necessary;
- authority/freshness metadata where relevant;
- context/retrieval trace for debugging.

Do not solve missing context by loading entire datasets into prompts.

## Evals philosophy

Evals are part of development, not a final polishing phase.

Before changing prompt/model/playbook/context/retrieval/tool behavior:
1. identify relevant golden cases;
2. implement narrowly;
3. run relevant regressions;
4. do not rewrite expected behavior simply to make a failing implementation pass.

## Current execution state

Always defer to `docs/00_EXECUTION_CONTROL.md` for:
- active objective;
- current phase;
- checkpoint/gaps;
- done criteria;
- explicitly forbidden work.

If this file and `00_EXECUTION_CONTROL.md` disagree on sequencing, stop and report the discrepancy rather than guessing.