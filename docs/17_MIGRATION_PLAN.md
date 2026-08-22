# MIND INTELLIGENCE — MIGRATION PLAN

Status: DRAFT — execution planning only. NO SQL OR PRODUCTION CHANGE IS AUTHORIZED BY THIS DOCUMENT YET.

Purpose: translate `15_CURRENT_TO_TARGET_MAP.md` into an executable, reversible migration sequence with compatibility, validation and rollback.

## Required inputs
- `README_FIRST.md`
- `docs/00_EXECUTION_CONTROL.md`
- `docs/00_ARCHITECTURE.md`
- `docs/02_TARGET_DATA_MODEL.md`
- `docs/07_CURRENT_STATE_2026-08-22.md`
- `docs/09_SOURCE_OF_TRUTH_DRAFT.md`
- `docs/15_CURRENT_TO_TARGET_MAP.md`
- `docs/16_TARGET_ADJUSTMENTS_FROM_RECONCILIATION.md`
- checkpoint branch `checkpoint/pre-mind-intelligence-architecture`

## Migration doctrine
1. No big-bang rewrite.
2. Add new target structures before removing old ones.
3. Preserve IDs where this materially reduces FK/cutover risk.
4. Prefer compatibility wrappers/views during transition.
5. Backfill before switching reads.
6. Switch reads before switching writes unless the dependency requires otherwise.
7. Validate against golden behavior and deterministic data checks.
8. Retire legacy only after consumer verification.
9. Production migration must have rollback/recovery path.
10. Security/RLS changes must be explicit per object, not blanket toggles.

## Wave 0 — Recovery, inventory, environments

### Goal
Create a trustworthy baseline and a safe place to test target migrations before production.

### Required work
- recover/archive the 71 applied migration statements not represented as files;
- obtain a structural schema baseline or equivalent reproducible schema snapshot;
- export/version non-secret curated configuration currently living only in DB;
- inventory Edge Function/RPC consumers and webhook entry points;
- inventory `mind-assets` and required public URLs;
- document current secrets by name/environment without exposing values;
- establish development/staging database path;
- map all 12 RLS-disabled tables and their consumers;
- review SECURITY DEFINER/search_path/public-execute exposures relevant to target cutover.

### Exit criteria
- current production state is recoverable enough to perform non-destructive target work;
- there is a test environment or reproducible local/staging path;
- no known curated config has a single unversioned copy;
- first target migration can be tested away from production.

### Rollback
No production mutation in Wave 0 except explicitly approved backup/export/security emergency actions.

## Wave 1 — Canonical identity and catalog foundations

### Add
- `people.people`
- `people.contact_points`
- `people.identity_merges`
- `people.organizations`
- `people.affiliations`
- `crm.contacts`
- `integrations.external_refs`
- `integrations.value_mappings`
- `catalog.product_families`
- `catalog.products`
- `catalog.product_runs`
- `catalog.product_components`
- minimum privacy tables required for future contactability

### Backfill
- map `crm.pessoas` → canonical people while preserving UUIDs where safe;
- split email/phone into contact points;
- move HubSpot/provider IDs into external refs;
- split `catalogo.produtos` into products vs runs;
- preserve legacy product codes as aliases/mappings.

### Compatibility
- keep current `crm.pessoas` and `catalogo.produtos` readable during transition;
- expose compatibility functions/views where current Edge Functions require them;
- no current Sales/Concierge consumer changes yet unless required for tests.

### Tests
- same known person resolves to one canonical person by email/phone/external ref;
- no duplicate person created by Treble vs app identity;
- Mind Summit canonical product has separate 2025/2026 runs;
- all current product references map deterministically;
- merge-history audit preserved.

### Legacy retirement
None in this wave.

## Wave 2 — Summit and commercial canonicalization

### Add/evolve
- `summit.editions` linked 1:1 to product run;
- keep/evolve `summit.locations`, sessions, navigation, polls, exhibitors as required;
- move speaker identity to people while session role remains Summit-specific;
- `commercial.offers`
- `commercial.pricing_periods`
- `commercial.offer_prices`
- `commercial.offer_inclusions`
- `commercial.discount_rules`
- `commercial.discount_codes`

### Backfill
- `summit.events` → edition facet;
- `comum.speakers` → people/profiles/affiliations/assets;
- `summit.offers` → offer + pricing structures;
- `summit.coupons` → discount codes/rules;
- `summit.commercial_rules` → commercial rules and/or decision policies.

### Compatibility
Current price/checkout/volume RPCs must continue returning the same authoritative results while their physical source changes.

### Tests
- compare all active MIND/VIP/PRIME values against pre-migration production values;
- lot/current-date behavior unchanged;
- volume/group calculations unchanged;
- checkout URLs/UTM attribution preserved;
- agenda/session/speaker queries preserve current results.

### Cutover gate
Sales cannot switch to the new commercial source until deterministic comparison tests pass.

## Wave 3 — Knowledge and product content

### Add/evolve
- `knowledge.sources`
- `knowledge.concepts`
- `knowledge.claims`
- `knowledge.claim_sources`
- `knowledge.documents`
- `knowledge.document_chunks`
- product/person concept relations;
- product content under catalog/appropriate editorial source.

### Backfill
- common and line-specific knowledge documents;
- meaningful Summit knowledge;
- taxonomy split between semantic concepts vs operational enums;
- curated materials split into assets/documents/playbook-use metadata as appropriate.

### Compatibility
Keep current search functions/views until new retrieval contracts pass recall/precision tests.

### Tests
- exact operational facts still come from structured data, not vector retrieval;
- known scientific/product questions retrieve correct sources;
- stale content cannot override current price/agenda;
- source provenance remains inspectable.

## Wave 4 — Shared engagement and intelligence

### Add/evolve
- canonical `engagement.conversations`
- `engagement.messages`
- `engagement.entry_points`
- `engagement.entry_contexts`
- `engagement.interactions`
- `intelligence.facts`
- `intelligence.insights`
- `intelligence.intents`
- `intelligence.summaries`
- `intelligence.product_fit`

### Backfill/merge
- Concierge conversations/messages;
- Treble conversations/messages;
- UTM/origin context;
- participant memory/interests/commercial signals/objectives;
- summaries/projections.

### Compatibility
- Treble session external ID maps to canonical conversation;
- app/device sessions can continue channel-specific auth/session behavior;
- old Treble/Concierge stores remain available until adapters are cut over.

### Tests
- same person can have separate WhatsApp/app conversations with shared memory;
- returning person is not re-qualified from zero;
- facts do not duplicate contact/purchase/price canonical domains;
- inferred insights retain confidence/provenance/evidence.

## Wave 5 — Agent API, behavior, evals and Sales Summit cutover

### Add/evolve
- `playbooks`
- `decisioning`
- `agents`
- `agent_api`
- run/context/retrieval trace;
- Sales golden eval dataset.

### Runtime migration
- Treble remains ingress/egress adapter;
- shared orchestrator handles Sales turn;
- `sales_summit` profile controls context/playbook/tools;
- current commercial guardrails are preserved;
- old RPCs can wrap new Agent API temporarily.

### Mandatory behavioral acceptance
Conversation A:
“Oi, sou Adriana, trabalho na Empresa X. Queria saber mais sobre o VIP.”

Conversation B later:
“Oi, voltei. Minha preocupação é que dois dias fora é muito.”

System must preserve identity/company evidence/VIP interest/history/new objection/current authoritative pricing and respond according to Sales Behavior Spec without restarting qualification.

### Hard-failure gates
- invented/wrong price;
- invented agenda/speaker/inclusion;
- unauthorized discount;
- redundant known-data questioning;
- lost B2B signal;
- broken checkout attribution;
- lost Treble webhook/idempotency behavior.

### Cutover
Only after deterministic tests + golden evals + E2E Treble test pass.

## Wave 6 — Concierge Summit cutover

### Runtime migration
- keep app/auth/device ingress behavior;
- use same canonical identity, engagement and intelligence;
- use `concierge_summit` profile;
- expose agenda/navigation/reservation/feedback/material tools through Agent API.

### Tests
- person who interacted with Sales is recognized in Concierge without duplicate identity;
- ticket/access and agenda context are correct;
- recommendations use declared goals/interests without invasive diagnosis;
- session feedback/attendance/planned-but-missed data is preserved;
- day-1 dossier can support day-2 planning.

## Wave 7 — Privacy/contactability + Outbound

### Add/finalize
- `privacy.consents`
- `privacy.contactability`
- `privacy.suppressions`
- `privacy.communication_preferences`
- `privacy.data_requests`
- outbound workflow state/actions.

### Rules
- suppression/contactability is deterministic and blocks LLM send decisions;
- outbound reuses Sales intelligence/runtime, not a parallel person/database;
- sends/follow-ups are idempotent and auditable.

## Wave 8 — Service/CS/Support/Researcher and broader product lines

Build shared service domain and profiles only after Sales/Concierge core is stable.

Expand Institute, Dash and Events using the same canonical identity/catalog/knowledge/runtime contracts.

## Wave 9 — Legacy retirement and advanced hardening

Candidates only after usage verification:
- duplicate Treble conversation/message tables;
- compatibility RPCs;
- abandoned `treble-agent` v4;
- duplicate knowledge tables/views;
- staging/legacy person/product facades;
- redundant audit/config stores.

Complete security hardening, RLS review, performance optimization and expanded evals.

---

## Cross-wave migration checklist

Every physical migration PR must state:
1. scope;
2. affected current objects;
3. target objects;
4. data/config preservation;
5. dependencies/consumers;
6. forward SQL;
7. backfill;
8. RLS/grants/policies;
9. verification queries/tests;
10. rollback/recovery;
11. compatibility strategy;
12. legacy-retirement condition;
13. whether production deploy is authorized.

## Current implementation authorization

NONE.

The next technical action is Wave 0 planning/execution for recovery + environment safety. No Wave 1 schema migration should start until Wave 0 exit criteria are met and the Source of Truth is sufficiently closed.