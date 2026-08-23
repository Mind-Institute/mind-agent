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
- `docs/19_LEGACY_REUSE_AND_MIGRATION_POLICY.md`
- checkpoint branch `checkpoint/pre-mind-intelligence-architecture`

## Migration doctrine
1. No big-bang rewrite.
2. Add new target structures before removing old ones.
3. Preserve IDs where this materially reduces FK/cutover risk.
4. Prefer compatibility wrappers/views during transition.
5. Backfill only data/config that is approved for reuse or required for operational continuity.
6. Switch reads before switching writes unless the dependency requires otherwise.
7. Validate against golden behavior and deterministic data checks.
8. Retire current structures only after consumer verification.
9. Production migration must have rollback/recovery path.
10. Security/RLS changes must be explicit per object, not blanket toggles.
11. Current-system content is reviewed **just in time per target object**. Nothing is migrated merely because it exists.

## Required per-object decision for Waves 1–5

When implementing each target object, inspect the semantically corresponding current-system object(s) and classify the relevant data/behavior as:
- `REUSE`
- `TRANSFORM`
- `REBUILD`
- `DO NOT MIGRATE`

The implementation PR must record that decision and why.

`DO NOT MIGRATE` does not authorize deleting a live object before consumer/cutover verification.

## Wave 0 — Recovery, minimum inventory, environment safety

### Goal
Have enough recovery and environment safety to begin non-destructive target work without turning the current system into a separate migration project.

### Completed
- recovered/archived all 71 applied migration statements that were previously missing from Git;
- recovered production-only Edge Function code into the pre-architecture archive.

### Required work before first target migration
- obtain a structural schema baseline or equivalent reproducible schema snapshot, preferably automated;
- identify the consumers/contracts that could be affected by the **first target migration** and expand this inventory just in time as later objects are touched;
- document required secret names/dependencies without exposing values;
- establish a safe development/staging database path;
- identify RLS/SECURITY DEFINER/search_path/public-execute risks relevant to the objects that the first target migration will touch.

### Not a Wave 0 blocker
- bulk export/migration of unvalidated prompts, playbooks, templates, AI-generated configuration or commercial content;
- review of all current business content before implementation;
- backfill of Concierge interaction data, which is test data;
- full inventory of every asset or consumer unrelated to the next target change;
- full-bank security cleanup before target implementation.

Current content/config may remain safely in the current system and be reviewed when the corresponding target object is built.

`mind-assets` is a blocker only when a target/cutover step depends on an asset whose continuity is not otherwise protected.

### Exit criteria
- current production structure is recoverable/reproducible enough for comparison and rollback;
- there is a safe dev/staging path for the first target migration;
- dependencies that can break from the first target change are known;
- required secret dependencies are known without copying secret values;
- security risks relevant to the first target objects are identified;
- no operational dependency required for the first cutover depends on an unknown single copy.

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

### Just-in-time current-system review
Before backfill, compare target objects with the relevant current structures, including `crm.pessoas`, identity/external-ref stores, `catalogo.produtos`, product components and mappings.

For each source decide `REUSE / TRANSFORM / REBUILD / DO NOT MIGRATE`.

### Candidate backfill when approved
- map trustworthy real people into canonical people while preserving UUIDs where safe;
- split validated email/phone into contact points;
- move known provider IDs into external refs;
- map validated product/run records into the target catalog;
- preserve required legacy product codes as aliases/mappings.

Do not backfill test/untrusted records solely because they exist.

### Compatibility
- keep current identity/catalog structures readable during transition;
- expose compatibility functions/views where live consumers require them;
- no current Sales/Concierge consumer changes yet unless required for tests.

### Tests
- same known person resolves to one canonical person by email/phone/external ref;
- no duplicate person created by Treble vs app identity;
- Mind Summit canonical product has separate 2025/2026 runs;
- required current product references map deterministically;
- merge-history audit preserved when merge history is reused.

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

### Just-in-time current-system review
Compare each target object with corresponding current Summit/commercial structures.

Operational truth needed for continuity (for example current price/lot/checkout output) must be validated deterministically.

Commercial arguments, rules or content are **not approved merely because they are stored today**. Review them with Adriana when they are about to become target business truth.

### Candidate backfill when approved
- validated Summit edition/session/location/speaker data;
- validated offer/pricing records;
- validated discount codes/rules;
- only commercial rules explicitly approved for target use.

### Compatibility
Current price/checkout/volume RPCs must continue returning authoritative results until the new source passes deterministic comparison and cutover.

### Tests
- compare all active MIND/VIP/PRIME values against the currently authoritative operational source;
- lot/current-date behavior correct;
- approved volume/group calculations correct;
- checkout URLs/UTM attribution preserved;
- agenda/session/speaker queries preserve validated current results.

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

### Just-in-time current-system review
Inspect current knowledge/product content as candidate material, not as automatically approved truth.

For every migrated source/content set decide `REUSE / TRANSFORM / REBUILD / DO NOT MIGRATE` and preserve provenance.

### Candidate backfill when approved
- authoritative or explicitly approved Summit/product content;
- validated scientific/source material;
- useful taxonomy/content that survives review;
- assets/documents/material metadata required by the Sales runtime.

### Compatibility
Keep current search functions/views only as long as live consumers need them and until new retrieval contracts pass tests.

### Tests
- exact operational facts come from structured authoritative data, not vector retrieval;
- known scientific/product questions retrieve approved sources;
- stale/unapproved content cannot override current price/agenda;
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

### Just-in-time current-system review
Inspect Treble and other real interaction stores for records that are operationally useful.

**Concierge interaction data currently in the system is test data and is not backfilled into the target.**

AI-derived memory/interests/signals/objectives/summaries are not migrated unless explicitly validated for a real record and useful to the target.

### Candidate backfill/merge when approved
- real Treble conversations/messages needed for continuity;
- validated UTM/origin context;
- other real engagement records that pass object-level review.

### Compatibility
- Treble session external ID maps to canonical conversation;
- app/device sessions can continue channel-specific auth/session behavior;
- current stores remain available until adapters are cut over.

### Tests
- same person can have separate WhatsApp/app conversations with shared memory;
- returning person is not re-qualified from zero when validated history exists;
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

### Business-truth rule
Sales behavior is built from:
1. the approved Sales Behavior Spec;
2. explicit business decisions validated with Adriana;
3. validated authoritative operational facts;
4. approved knowledge sources.

Current Treble prompts/playbooks/commercial copy may be inspected as reference, but are not promoted automatically into the target.

### Runtime migration
- Treble remains ingress/egress adapter;
- shared orchestrator handles Sales turn;
- `sales_summit` profile controls context/playbook/tools;
- validated commercial guardrails are preserved;
- current RPCs can wrap new Agent API temporarily where useful.

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
- new real session feedback/attendance/planned-but-missed data is preserved;
- day-1 summary can support day-2 planning.

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
4. per-object decision: REUSE / TRANSFORM / REBUILD / DO NOT MIGRATE;
5. dependencies/consumers;
6. forward SQL;
7. backfill, if any;
8. RLS/grants/policies;
9. verification queries/tests;
10. rollback/recovery;
11. compatibility strategy;
12. current-object retirement condition;
13. whether production deploy is authorized.

## Current implementation authorization

NONE until the reduced Wave 0 exit criteria above are met.

The next technical action remains Wave 0, but Wave 0 is now intentionally limited to the recovery/environment safety needed to begin the first target migration. Broad migration/review of untrusted content is explicitly deferred to just-in-time object review.
