# MIND INTELLIGENCE — TARGET ADJUSTMENTS FROM RECONCILIATION

Status: NORMATIVE
Date: 2026-08-22

This document records target-architecture adjustments discovered by reconciling the frozen design with the real Supabase/GitHub state. These are not invitations to reopen the architecture. They are corrections required so the target preserves durable capabilities already present in the real system.

Until `00_ARCHITECTURE.md` and `02_TARGET_DATA_MODEL.md` are folded forward with these items, this document has equal normative authority for these specific additions.

## 1. `people.identity_merges`

Add an explicit identity-merge audit/history representation.

Purpose:
- preserve surviving person and merged person;
- reason/source;
- process/actor;
- timestamp;
- optional evidence/audit metadata.

Reason: the current system already has `engagement.identidade_fusoes`; identity merge is high-impact and must remain traceable.

## 2. `catalog.product_components`

Add many-to-many product composition/relationship support.

Minimum semantics:
- product_id;
- component_product_id;
- relation_type;
- optional validity/version.

Reason: `parent_product_id` alone cannot represent real bundle/component/credential-path relationships already present in `catalogo.produto_componentes`.

## 3. `commercial.discount_codes`

Add explicit redeemable codes/coupons separate from abstract `discount_rules`.

Minimum semantics:
- code;
- rule/offer/product_run relationship;
- validity;
- usage limits/state;
- conditions.

Reason: current `summit.coupons` represents concrete codes; a rule is not the same thing as a code.

## 4. `engagement.entry_points`

Add reusable entry-point definitions distinct from per-arrival `entry_contexts`.

Examples:
- site button / source code;
- default opening behavior;
- suggested audience hint;
- attribution defaults;
- integration mapping reference where needed.

`entry_contexts` remains the immutable/per-arrival captured context.

Reason: current `engagement.origens` encodes useful reusable definitions.

## 5. `privacy.data_requests`

Add data-subject request lifecycle under the privacy domain.

Examples:
- access;
- correction;
- deletion;
- other requests;
- status/timestamps/evidence.

Reason: current `engagement.data_requests` is a durable privacy capability and belongs in the privacy domain.

## 6. Preserve Summit-specific operational capabilities

The Summit target must explicitly allow product-specific capabilities already present and useful:
- polls;
- poll answers;
- exhibitors;
- route/navigation graph;
- event rules;
- attendee networking/contact requests.

Suggested physical concepts:
- `summit.polls`
- `summit.poll_answers`
- `summit.exhibitors`
- `summit.route_edges` or `navigation_edges`
- `summit.event_rules`
- `summit.networking_requests`

Do not force these into shared/global schemas for symmetry.

## 7. Retain infrastructure-level `platform` domain

Provider/model/embedding routing and low-level model-call telemetry may remain in a distinct `platform` schema (or equivalent infrastructure namespace).

Durable responsibilities:
- LLM providers;
- model catalog;
- model routing;
- embeddings configuration;
- low-level model-call telemetry.

`agents.runs` remains the semantic agent-run record and links to model-call telemetry rather than replacing provider infrastructure.

Reason: the current `platform.llm_*` model already captures a legitimate infrastructure responsibility separate from agent behavior.

## 8. `integrations.value_mappings`

Add mapping configuration for external vocabulary/value → canonical internal entity/value.

Examples:
- HubSpot property value → catalog product/product_run;
- external category code → canonical code.

This is different from `integrations.external_refs`, which maps entity identity/IDs across systems.

Reason: current `crm.mapa_produtos` represents this requirement.

## 9. Physical-name decision: keep `summit.locations` unless semantics require otherwise

The target conceptual model used the term `spaces`. The current `summit.locations` is already a rich and useful representation of hierarchical spaces/locations.

Decision:
- do not rename merely for aesthetic consistency;
- keep `summit.locations` as the recommended physical name unless migration design exposes a real semantic conflict.

## 10. Target invariants unaffected

These adjustments do NOT change the frozen core principles:
- one canonical person;
- contact point != external ref != CRM contact;
- product != product run;
- Intelligence != Playbook != Decisioning != Agent;
- shared engagement/intelligence across channel-specific conversations;
- commercial truth outside prompts;
- scientific knowledge distinct from product copy;
- Agent API hides topology;
- base context + just-in-time retrieval;
- deterministic privacy/contactability for outbound;
- eval-driven agent development.

## 11. Implementation rule

No table/function should be created solely from this document before `17_MIGRATION_PLAN.md` defines:
- dependency order;
- compatibility strategy;
- backfill;
- verification;
- rollback/recovery;
- legacy retirement conditions.
