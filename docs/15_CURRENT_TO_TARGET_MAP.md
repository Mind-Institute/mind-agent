# MIND INTELLIGENCE — CURRENT → TARGET MAP

Status: NORMATIVE INPUT FOR MIGRATION PLAN

Date of reconciliation: 2026-08-22

This document maps the observed production/prototype state to the frozen Mind Intelligence target architecture. It exists to prevent accidental loss of working behavior/data and to prevent the current prototype topology from becoming the target by inertia.

No database object should be dropped or renamed solely from this document. The migration plan must define sequence, compatibility, backfill, verification and rollback.

---

## 1. Classification legend

- **KEEP** — concept and placement are already sufficiently aligned; preserve with minor cleanup only.
- **MOVE** — concept is good but belongs to another target domain/schema.
- **EVOLVE** — preserve the concept/data, but change structure/semantics.
- **MERGE** — duplicated current representations converge into one target representation.
- **SPLIT** — one current object contains multiple responsibilities that belong to different target domains.
- **REBUILD** — behavior/value is useful, but current structure should not be preserved.
- **RETIRE** — legacy object can disappear after all consumers/data/config are migrated and verified.
- **TARGET ADJUSTMENT** — the real system revealed a durable requirement missing from the target docs; update target before implementation.

Priority:
- **P0** — security/recovery/integrity blocker before public go-live or destructive migration.
- **P1** — required for Sales/Concierge target runtime.
- **P2** — required before Outbound/CS or broader platform expansion.
- **P3** — later optimization/cleanup.

---

## 2. Global migration principles

1. Preserve useful behavior, data and curated configuration; do not preserve accidental topology.
2. Prefer stable IDs during migration where doing so materially reduces FK rewiring risk.
3. Never destroy the only recoverable copy of data/configuration.
4. Build compatibility layers where necessary; remove them only after consumers migrate.
5. Every target authority must be explicit before cutover.
6. No prompt/vector content can remain the authority for price, access, consent or other deterministic operational facts.
7. AI-derived insight never silently overwrites verified fact.
8. Sales and Concierge converge on shared identity/engagement/intelligence without forcing one infinite cross-channel conversation.
9. Migrations must be versioned in Git and tested against the target contracts.
10. Security hardening is part of migration, not a post-launch optional cleanup.

---

# PART A — TARGET ADJUSTMENTS DISCOVERED DURING RECONCILIATION

The real system exposed several durable requirements that should be added to the target model before implementation.

## A1. Identity merge history

### Current
`engagement.identidade_fusoes`

### Problem
The target defines canonical identity but not the audit/history of identity merges.

### Decision
**TARGET ADJUSTMENT — add `people.identity_merges` (or equivalent).**

Minimum semantics:
- surviving_person_id;
- merged_person_id;
- reason/source;
- performed_by / process;
- merged_at;
- optional evidence/audit metadata.

Why: identity merge is irreversible/high-impact and needs traceability.

Priority: **P1**.

---

## A2. Product composition / bundles

### Current
`catalogo.produto_componentes`

### Problem
The target had `parent_product_id`, but real product composition can be many-to-many. Example: a certification/offer composed of multiple formations.

### Decision
**TARGET ADJUSTMENT — add `catalog.product_components` (or `product_relations`).**

Minimum semantics:
- product_id;
- component_product_id;
- relation_type (component/bundle/prerequisite/credential_path/etc.);
- validity/version if needed.

Priority: **P2**.

---

## A3. Concrete coupon/discount codes

### Current
`summit.coupons`

### Problem
`commercial.discount_rules` alone does not represent actual redeemable codes cleanly.

### Decision
**TARGET ADJUSTMENT — add `commercial.discount_codes` (or `coupons`).**

Rules remain in `discount_rules`; concrete codes reference rules/offers/product runs.

Priority: **P1** for Sales if coupon flows remain active.

---

## A4. Entry-point definitions

### Current
`engagement.origens` + `engagement.utm_sessoes`

### Problem
Target had `entry_contexts`, but not the reusable definitions for named entry points/buttons with default opening behavior and attribution mapping.

### Decision
**TARGET ADJUSTMENT — add `engagement.entry_points`** for reusable source definitions; `entry_contexts` remains the per-arrival captured event/context.

Priority: **P1**.

---

## A5. Privacy data-subject requests

### Current
`engagement.data_requests`

### Decision
**TARGET ADJUSTMENT — add `privacy.data_requests`** (access/delete/correction/other requests and lifecycle).

Priority: **P2**.

---

## A6. Summit operational features omitted from target list

Real current Summit data includes durable product-specific capabilities not represented in the high-level target list:
- polls / poll answers;
- exhibitors;
- route/navigation graph;
- event rules;
- attendee networking/contact requests.

### Decision
**TARGET ADJUSTMENT — preserve these under `summit` if the product still needs them.**

Suggested target concepts:
- `summit.polls`
- `summit.poll_answers`
- `summit.exhibitors`
- `summit.route_edges` / `navigation_edges`
- `summit.event_rules`
- `summit.networking_requests`

Do not force them into generic shared schemas merely for uniformity.

Priority: **P1/P2 depending Concierge scope**.

---

## A7. LLM platform configuration

### Current
`platform.llm_providers`, `platform.llm_models`, `platform.llm_routes`, `platform.embeddings_config`, `platform.llm_calls`

### Problem
The target placed most agent runtime configuration in `agents`, but provider/model routing is infrastructure-level configuration and can remain distinct.

### Decision
**TARGET ADJUSTMENT — retain a `platform` (or equivalent infrastructure) schema** for provider/model/embedding routing and low-level model-call telemetry.

`agents.runs` remains the semantic agent-run record and should link to underlying model-call telemetry rather than duplicate every provider detail.

Priority: **P1**.

---

## A8. External value mappings

### Current
`crm.mapa_produtos`

### Problem
Not every external system value is a direct entity external ID. Some integrations require mapping external vocabulary/value → canonical internal entity/value.

### Decision
**TARGET ADJUSTMENT — add `integrations.value_mappings` (or equivalent mapping config).**

Priority: **P1/P2**.

---

# PART B — IDENTITY, PEOPLE, CRM AND PRIVACY

## B1. `crm.pessoas`

### Current role
De facto universal person table. It currently contains identity + HubSpot mirror + professional/commercial fields. A large number of FKs across the system point to it.

### Target
- `people.people` — canonical identity
- `people.contact_points` — email/phone/WhatsApp identifiers
- `people.affiliations` / `crm.contacts` — contextual/professional/commercial facets
- `integrations.external_refs` — HubSpot ID

### Classification
**SPLIT + EVOLVE — P1**

### Migration strategy
- Prefer preserving current `crm.pessoas.id` as the new `people.people.id` wherever possible. This reduces coordinated FK rewrite risk.
- Move email/WhatsApp to `people.contact_points`.
- Move HubSpot ID to `integrations.external_refs`.
- Create `crm.contacts` linked to the canonical person for commercial relationship state.
- Move company/cargo according to verified semantics: curated real-world affiliation → `people.affiliations`; CRM-entered sales context → CRM relationship fields until verified.
- Current `estagio` is CRM stage/context, not identity.

### Do not
Do not rename `crm.pessoas` in place and hope all semantics become correct.

---

## B2. `engagement.identidades`

### Current
Maps identifiers such as WhatsApp/email/Yazo/Eduzz/HubSpot/device/Treble session to one person.

### Target mapping
**SPLIT — P1**

- email/phone/WhatsApp → `people.contact_points`
- HubSpot/Eduzz/Yazo provider IDs → `integrations.external_refs`
- Treble session external id → external ref on conversation/integration, not human contact point
- device id → `engagement.devices` / runtime session identity

Preserve verification/confidence metadata.

---

## B3. `engagement.identidade_fusoes`

### Classification
**MOVE — P1**

Target: `people.identity_merges`.

Preserve all rows and audit meaning.

---

## B4. `engagement.pessoa_perfil`

### Current
Small person-level profile (`idioma`, `anonimo`).

### Classification
**SPLIT/EVOLVE — P2**

- language preference may become person/profile/communication preference depending semantics;
- anonymous state is runtime/identity state, not a durable profile biography.

Do not create a generic profile dumping ground.

---

## B5. `engagement.verificacoes_email`

### Current
Operational email verification workflow.

### Classification
**EVOLVE — P2**

Target may be an operational verification table associated with `people.contact_points` or auth workflow. It does not need to be a headline domain object, but verification state must ultimately update the canonical contact point.

---

## B6. `crm.pessoas_interno`

### Current
Mixes attribution, owner, lead status, engagement, customer profile and unsubscribe state.

### Classification
**SPLIT — P1/P2**

Mapping:
- owner/status/pipeline-related → `crm`
- attribution fields → `engagement.entry_contexts` / integration mirror
- unsubscribe → `privacy.suppressions/contactability`
- profile/customer segmentation → CRM/intelligence based on whether verified vs inferred
- last contact → CRM/engagement derived data

Retire after each field has an explicit authority.

---

## B7. `crm.consents`

### Classification
**MOVE — P1 before outbound**

Target: `privacy.consents`.

Preserve:
- purpose;
- granted/revoked state;
- policy/version;
- displayed text;
- source/evidence;
- timestamps.

---

## B8. `engagement.data_requests`

### Classification
**MOVE — P2**

Target: `privacy.data_requests`.

---

## B9. `crm.leads_capturados`

### Current
Staging queue for bot-captured leads to HubSpot.

### Classification
**REBUILD/RETIRE — P2**

Target flow should use canonical person/contact + CRM relationship + integration outbox/sync state. Keep compatibility until HubSpot write path is replaced and verified.

---

## B10. `crm.acessos` + `intelligence.acessos_dado_pessoal`

### Classification
**MERGE — P2**

Target: `ops.audit_log` or dedicated privacy/security audit representation.

Keep subject/actor/function/agent/timestamp semantics.

---

# PART C — CATALOG AND PRODUCT IDENTITY

## C1. `catalogo.produtos`

### Current
Mixes canonical products and concrete product runs/editions/cohorts.

Examples include canonical-like rows (`mind`, placeholders) and run-specific rows (`mind-summit-2026`, `mind-journey-2025`, 2025 formations).

### Classification
**SPLIT + REBUILD — P1**

Target:
- `catalog.product_families`
- `catalog.products`
- `catalog.product_runs`

### Migration rules
- Mind Summit → one canonical product.
- Mind Summit 2025 / 2026 → product runs.
- Institute formations → canonical products; 2025 deliveries → product runs.
- Mind Journey → canonical product; 2025 → product run.
- Oxford no Conselho → canonical event product + run when edition-specific.
- Dash → canonical product/solution identity, not placeholder-only row.

Preserve legacy `codigo` as migration alias/mapping until all consumers move.

---

## C2. `catalogo.produto_componentes`

### Classification
**MOVE/EVOLVE — P2**

Target: `catalog.product_components` / relations.

Do not model many-to-many composition using only `parent_product_id`.

---

# PART D — SUMMIT PRODUCT DOMAIN

## D1. `summit.events`

### Current
Represents Mind Summit 2026 event instance with product code.

### Classification
**EVOLVE/RENAME — P1**

Target: `summit.editions` as 1:1 facet of `catalog.product_runs`.

Migration preference:
- preserve current event UUID as edition UUID where practical;
- add/require `product_run_id` UNIQUE;
- remove direct dependence on legacy `produto_codigo` after transition.

---

## D2. `summit.venues`

### Classification
**KEEP/EVOLVE — P1**

Target remains `summit.venues`.

Point it to edition/product run scope rather than ambiguous event code as architecture settles.

---

## D3. `summit.locations`

### Current
Rich hierarchical venue spaces, aliases, maps, accessibility, parent hierarchy.

### Classification
**KEEP/EVOLVE — P1**

Target document used the word `spaces`; current `locations` is already a useful representation. Physical rename is optional and should not be done just for aesthetics.

Recommendation: keep `summit.locations` unless a concrete semantic reason requires `spaces`.

This is a case where the target logical concept does not require a physical rename.

---

## D4. `summit.sessions`

### Classification
**KEEP/EVOLVE — P1**

Preserve data and IDs. Add/normalize edition/product-run relationship. Keep exact schedule/access data structured and authoritative.

Potential future normalization of arrays (`trilhas`, `ingressos`) should be eval/use-case driven; do not block Sales/Concierge for theoretical purity.

---

## D5. `comum.speakers` + `summit.session_speakers`

### Classification
**SPLIT/MOVE — P1**

`comum.speakers` → canonical `people.people` + `people.profiles/assets/affiliations`.

`summit.session_speakers` → `summit.session_people` with role per session.

Preserve current speaker UUID as canonical person UUID where safe to reduce remapping.

Speaker is a role, not a person type.

---

## D6. `summit.registrations`

### Current
Person ↔ event registration/ticket category.

### Classification
**SPLIT/EVOLVE — P1**

Potential target responsibilities:
- edition participation/registration → `summit.edition_people` (or registration table under Summit);
- entitlement/access → `commercial.access_rights`;
- transaction/payment → commercial order/payment domain, not Summit registration.

Do not infer purchase solely from registration row.

---

## D7. `summit.session_reservations`

### Classification
**KEEP/EVOLVE — P1 Concierge**

Target: `summit.reservations`.

Link to canonical person and session; preserve external Yazo reference via `integrations.external_refs` where needed.

---

## D8. `summit.polls`, `summit.poll_answers`

### Classification
**KEEP — P2 Concierge/event experience**

Add to target Summit domain.

---

## D9. `summit.exhibitors`

### Classification
**KEEP — P2**

Product-specific event data. Add to target Summit domain.

---

## D10. `summit.route_edges`

### Classification
**KEEP — P1/P2 Concierge**

Navigation is a real Concierge capability. Keep under Summit rather than moving to generic shared schema.

---

## D11. `summit.event_rules`

### Classification
**KEEP/EVOLVE — P1 Concierge**

Operational event rules can remain under Summit if they describe event behavior/instructions. Hard system policies (e.g. discount authority, privacy blocks) belong to `decisioning.policies`/privacy instead.

Split only when semantics demand it.

---

## D12. `engagement.contatos`

### Current
Participant-to-participant contact/networking request.

### Classification
**MOVE — P2**

Target: `summit.networking_requests` if networking remains a product feature.

---

# PART E — COMMERCIAL

## E1. `summit.offers`

### Current
Contains offer code/name, amount, payment conditions, checkout URL, eligibility, validity windows, demand/scarcity flags.

### Classification
**SPLIT/MOVE — P1**

Target:
- `commercial.offers` — offer identity (MIND/VIP/PRIME/Corporate etc.)
- `commercial.pricing_periods` — lot/time window
- `commercial.offer_prices` — amount/currency per period
- `commercial.offer_inclusions` — inclusions/access
- checkout metadata via offer/integration contract

Preserve existing price guardrail behavior throughout migration.

Do not cut over Sales until price comparison tests pass against current known values.

---

## E2. `summit.coupons`

### Classification
**MOVE — P1 if active**

Target: `commercial.discount_codes` linked to `discount_rules`/offer/run.

---

## E3. `summit.commercial_rules`

### Classification
**MOVE/SPLIT — P1**

- pricing/volume/discount eligibility → `commercial.discount_rules`
- non-commercial hard behavior → `decisioning.policies`

Keep machine-readable config; do not move rules into prose prompts.

---

## E4. Pricing/checkout RPC logic

Current valuable behavior includes functions such as:
- `mind_precos_por_volume()`
- `mind_virada_de_lote()`
- `mind_checkout_url()`
- `treble_agent_context()` commercial assembly

### Classification
**REUSE LOGIC / REBUILD CONTRACT — P1**

Target: semantic `agent_api` functions over `commercial`.

Examples:
- `get_commercial_context()`
- `compare_offers()`
- `get_current_price()`
- checkout/tool function with attribution

Preserve guardrails; change physical sources behind the contract.

---

## E5. `crm.pessoa_produtos`

### Current
Mirror of what a person acquired/accesses.

### Classification
**MOVE/EVOLVE — P1/P2**

Target primarily `commercial.access_rights`, backed by normalized orders/payments/invites/upgrades.

If a HubSpot-derived product relationship is not verified purchase/access, store it as integration/CRM evidence, not entitlement.

---

## E6. Orders/payments/refunds

### Current
Not yet represented comprehensively in target production data model; external providers are expected sources.

### Classification
**NEW TARGET IMPLEMENTATION — P2**

Do not fabricate historical transactional certainty from incomplete CRM rows. Ingest provider events with provenance.

---

# PART F — ENGAGEMENT AND CONVERSATIONS

## F1. `engagement.conversas`

### Current
Concierge/app conversation store.

### Classification
**EVOLVE INTO CANONICAL CORE — P1**

Target: `engagement.conversations`.

Preserve current IDs/data. Expand fields to support product/run/profile/channel/status/external refs where needed.

---

## F2. `engagement.mensagens`

### Classification
**EVOLVE INTO CANONICAL CORE — P1**

Target: `engagement.messages`.

Preserve raw content, sender role, client id, timestamps. Add/normalize agent run linkage and channel metadata.

---

## F3. `treble.conversations`

### Current
Parallel WhatsApp/Sales conversation store with Sales state embedded in columns.

### Classification
**MERGE — P1**

Target:
- conversation identity/history → `engagement.conversations`
- `session_external_id` → external ref/integration metadata
- phone → `people.contact_points`
- UTM/origin → `engagement.entry_contexts`
- audience/intent/objection → `intelligence` / decisioning state
- stage/next state → decisioning/playbook state
- checkout/purchase flags → commercial/interactions/derived state
- human handoff → service/agents/next actions according to use

Treble remains a channel adapter, not a separate memory system.

---

## F4. `treble.messages`

### Classification
**MERGE — P1**

Target: `engagement.messages`.

Map roles to canonical sender types. Preserve tool-call audit by linking to `agents.runs`/tool calls/retrieval trace rather than raw unstructured JSON only.

---

## F5. `engagement.agent_sessions`, `engagement.dispositivos`

### Classification
**KEEP/EVOLVE INTERNAL RUNTIME — P1 Concierge**

These support auth/device/session continuity and do not have to become headline business-domain tables. Keep if useful, but make canonical person/conversation references explicit.

---

## F6. `engagement.origens`

### Classification
**EVOLVE — P1**

Target: `engagement.entry_points`.

Keep reusable definitions such as button/source, suggested audience, opening message and HubSpot mappings only if each field still has a clear owner.

Do not mix external system field mapping indefinitely; move mapping config to integrations where appropriate.

---

## F7. `engagement.utm_sessoes`

### Classification
**EVOLVE — P1**

Per-arrival attribution → `engagement.entry_contexts`.

Short token bridge to WhatsApp may remain an implementation table if needed, but it should produce a canonical entry context.

---

## F8. `engagement.session_interests` + `treble.conversation_interests`

### Classification
**MERGE/REBUILD — P1**

Target: primarily `intelligence.insights` (interest/preference etc.) with evidence/confidence/provenance.

Do not preserve “interest” as a generic bag of nouns.

---

## F9. `engagement.agente_eventos`

### Classification
**MERGE/RETIRE — P2**

Map operationally to `agents.runs/actions`, `ops.domain_events` or `engagement.interactions` depending event type. Retire generic overlap after mapping.

---

## F10. `engagement.feedbacks`, `engagement.sessao_feedback`, `engagement.evento_feedback`, `engagement.nps`

### Classification
**SPLIT/MOVE — P1/P2 Concierge**

- session/event feedback content → `summit.feedback`
- submission/action timeline → `engagement.interactions`
- cross-product customer satisfaction → `service.satisfaction` when semantics are relationship-level rather than event-specific

Keep explicit product/run scope.

---

## F11. `engagement.jornada_sessao` + `engagement.jornada_eventos`

### Classification
**SPLIT/EVOLVE — P1 Concierge**

Current semantics include plan/intention/attendance/absence/frustrated demand.

Target mapping:
- reservations/planned → Summit reservation/planning model
- attendance → `summit.attendance`
- behavioral timeline → `engagement.interactions`
- reason/insight about unmet demand → structured Summit analytics/intelligence where appropriate

Preserve ability to answer:
- where person planned to go;
- where person attended;
- where person wanted to go but could not;
- why.

Do not lose current analytics use cases during normalization.

---

# PART G — INTELLIGENCE

## G1. `intelligence.participante_memoria`

### Current
Generic memory key/value with confidence, source, evidence, status, validity, importance, supersession.

### Classification
**SPLIT/EVOLVE — P1**

Strong current mechanics worth preserving:
- confidence;
- evidence_message_id;
- status;
- validity;
- supersession;
- importance.

Target:
- objective long-tail factual memory → `intelligence.facts`
- inferred/user-relevant interpretation → `intelligence.insights`

Do not migrate canonical fields (email, purchase, price, affiliation) into facts just because they exist in memory.

---

## G2. `intelligence.memoria_regras` + `intelligence.memoria_bloqueios`

### Classification
**KEEP/EVOLVE AS MEMORY GOVERNANCE — P1**

These encode what may be inferred/stored and confidence thresholds. The target docs did not need a named headline table, but the capability is valuable.

Recommendation: retain under `intelligence` as memory/extraction policies or map to agent guardrails where appropriate.

Do not bury these rules only in prompts.

---

## G3. `intelligence.participante_contexto`

### Current
Aggregated professional context, needs, preferences, priorities, conversation summary, commercial context.

### Classification
**EVOLVE INTO DERIVED SUMMARY/PROJECTION — P1**

Target: `intelligence.summaries` + on-demand Base Context projections.

It should be derived from canonical facts/insights/CRM/commercial, not become an alternate source of truth.

---

## G4. `intelligence.participante_objetivos`

### Classification
**MOVE/EVOLVE — P1 Concierge**

Target primarily `intelligence.insights` with type goal/need/decision_pending, evidence and validity.

If a durable success goal later exists for a customer relationship, that belongs in `service.success_goals`.

---

## G5. `intelligence.perguntas_feitas`

### Classification
**EVOLVE — P2**

Useful behavior: avoid asking repetitive questions and remember refusals.

Target can be represented as `engagement.interactions` (question asked/answered/refused) plus conversation/summary projection. Do not necessarily preserve as a standalone canonical table.

---

## G6. `intelligence.recomendacoes`

### Classification
**SPLIT — P1 Concierge**

- recommendation decision/rationale → `decisioning.decisions`
- resulting recommendation/action → `agents.actions` or product-specific recommendation record if analytics require one
- relevant user response → `engagement.interactions`

Preserve ability to measure recommendation → attendance/value.

---

## G7. `intelligence.sinais_comerciais`

### Classification
**MOVE/EVOLVE — P1 Sales**

Target: `intelligence.insights` (buying_signal, interest, need, constraint etc.) plus next actions/deal updates when warranted.

Consent/contact request fields must move to privacy/engagement rather than remain inside commercial signal.

---

## G8. `intelligence.dossies`

### Classification
**EVOLVE — P1 Concierge**

Target: a generated summary/artifact linked to person/product run, likely `intelligence.summaries` with dossier type or a dedicated generated-artifact representation if delivery lifecycle requires it.

Do not store the dossier as the only copy of underlying facts.

---

# PART H — KNOWLEDGE, CONTENT, TAXONOMY AND MATERIALS

## H1. `comum.knowledge_sources`

### Classification
**MOVE/EVOLVE — P1**

Target: `knowledge.sources` with stronger source authority/version/provenance semantics.

---

## H2. `comum.knowledge_documents` + product-line `*.knowledge_documents`

### Classification
**MERGE/EVOLVE — P1**

Target: `knowledge.documents` with explicit product/product_run/line scope and provenance.

Do not maintain five structurally duplicated knowledge document tables unless a compelling operational reason appears.

Current product-line tables are mostly empty except Summit; migrate meaningful rows and preserve scope.

---

## H3. `comum.knowledge_chunks` + product-line `*.knowledge_chunks`

### Classification
**MERGE/EVOLVE — P1/P2**

Target: `knowledge.document_chunks`.

Preserve full-text and embedding metadata only when useful. Model/dimension/index compatibility must remain explicit.

Do not generate embeddings until ingestion/versioning and authoritative-source rules are established.

---

## H4. `comum.taxonomy`

### Current
Mixes semantic concepts and operational taxonomy/reference values.

### Classification
**SPLIT — P1/P2**

- scientific/semantic concepts → `knowledge.concepts` + aliases
- ICP/customer segmentation → CRM/intelligence reference data
- operational reason codes (e.g. absence) → owning product/domain reference tables

Do not make `knowledge.concepts` a dumping ground for every enum.

---

## H5. `comum.materiais`

### Current
Videos/testimonials/pages/PDFs with use guidance, audiences, objections, ICP, transcript, summary.

### Classification
**SPLIT/EVOLVE — P1 Sales**

Potential target:
- asset/document/transcript → `knowledge.documents` / storage
- product-facing asset/material → product-specific `summit.materials` or catalog content link
- approved “when to use” sales guidance → playbook move/example/strategy metadata
- audience/ICP targeting → playbook/intelligence relation, not hidden in an asset row only

Preserve useful curated content before redesign.

---

## H6. Mind/institutional/product content views

### Current
`mind.knowledge_*`, union views and related facades.

### Classification
**REBUILD/RETIRE — P2**

Target semantic contracts should be served by `agent_api`/safe API views over canonical knowledge. Keep compatibility views only until consumers move.

---

# PART I — PLAYBOOKS, AGENTS, PROMPTS, TOOLS AND DECISIONING

## I1. `treble.prompts`

### Current
Modular prompt blocks: base, tone, audience playbooks, objections etc.

### Classification
**SPLIT/EVOLVE — P1**

- stable domain competence → `playbooks`
- actual model instructions/system prompt artifacts → `agents.prompt_versions`
- product facts/copy → catalog/knowledge/commercial, not prompts
- hard rules → decisioning/commercial/privacy policies

Use current prompt content as source material, not as target ontology.

---

## I2. `concierge.prompts`

### Classification
**SPLIT/EVOLVE — P1 Concierge**

Same principle as Treble prompts. Converge prompt versioning across profiles while preserving Concierge-specific behavior.

---

## I3. `concierge.ferramentas`

### Classification
**MOVE/EVOLVE — P1**

Target:
- `agents.tool_registry`
- `agents.profile_tools`
- capability/action scopes

Preserve JSON schemas, write/read classification, confirmation requirement, timeouts/retries where still useful.

---

## I4. `concierge.intencoes`

### Classification
**EVOLVE — P1**

Intent recognition ultimately produces `intelligence.intents`/routing decisions. Config mapping intent → route/tool/effort may move to agent profile/capability routing configuration.

Avoid a fixed regex intent router becoming the architectural brain.

---

## I5. `concierge.config`, `feature_flags`, `templates`

### Classification
**SPLIT/KEEP — P1/P2**

- agent behavior config → agents/profile config
- feature flags → infrastructure/app feature flag layer
- user-visible template copy → product/app content/template layer

Do not move every key/value into one global config table.

---

## I6. `concierge.regras_proativas` + `concierge.proativo_fila`

### Classification
**EVOLVE — P2**

Target:
- trigger/rule strategy → decisioning/policies/playbook or product-specific proactive rules
- scheduled next actions → `decisioning.next_actions` / queue/outbox
- delivery state → agents/actions/integrations

Useful pattern for future Outbound/Concierge proactive behavior, but contactability must gate external messaging.

---

## I7. `concierge.ferramenta_chamadas`

### Classification
**MERGE/EVOLVE — P1**

Target: agent run/tool-call/retrieval trace telemetry.

Keep input/output/status/latency/idempotency; link to agent run and message.

---

## I8. `concierge.integracao_logs`

### Classification
**MOVE/EVOLVE — P2**

Target: `integrations.sync/webhook/error logs` or `ops.audit_log` depending event type.

---

## I9. `concierge.config_auditoria`

### Classification
**MOVE/MERGE — P2**

Target: `ops.audit_log` for configuration/admin changes.

---

## I10. `concierge.avaliacoes` + `concierge.avaliacao_execucoes`

### Classification
**MOVE/EVOLVE — P1**

Target:
- `evals.cases`
- `evals.expected_behaviors`
- `evals.runs`
- `evals.scores/failures`

Preserve existing cases as seed material; add Sales golden conversations before Sales cutover.

---

## I11. `platform.llm_*`

### Classification
**KEEP/EVOLVE — P1**

Keep low-level provider/model/routing infrastructure in `platform`.

Link semantic agent run → one or more low-level model calls.

Do not duplicate provider model catalog into every agent profile.

---

# PART J — API, RPCs AND EDGE FUNCTIONS

## J1. Existing `api.*` functions

### Current
Already forms an embryonic semantic API for app/agent use.

### Classification
**KEEP/EVOLVE — P1**

Decision:
- safe browser/app contracts may remain in `api`;
- internal agent semantic tools move/converge into `agent_api`;
- do not duplicate same function in both schemas without distinct consumer/security semantics.

Each existing function must be assigned one of:
- keep as public/app API;
- move to agent_api;
- compatibility wrapper;
- retire after consumer migration.

---

## J2. Public `mindagent_*` and `treble_agent_*` RPCs

### Classification
**REBUILD CONTRACT / COMPATIBILITY — P1**

Preserve working behavior, especially:
- identity/context lookup;
- commercial context;
- search;
- turn persistence;
- checkout/volume logic.

Expose target behavior through semantic Agent API and keep old RPCs as wrappers until Edge Functions migrate.

---

## J3. `treble-inbound-agent`

### Current value
Working Treble webhook handling + attribution + context + OpenAI + guardrails + persistence.

### Classification
**REBUILD AROUND SHARED CORE — P1 Sales**

Target decomposition:
- Treble ingress adapter/webhook validation;
- idempotency/raw event persistence;
- shared `orchestrate-turn` runtime with `sales_summit` profile;
- Treble response adapter/session keys.

Preserve price guardrails and current channel contract.

Do not rewrite everything simultaneously; migrate behind compatible ingress.

---

## J4. `mindagent-chat`

### Current value
Strong auth/session/identity/profile/history/retrieval/personalization flow.

### Classification
**REBUILD AROUND SHARED CORE — P1 Concierge**

Target:
- app/auth ingress remains channel-specific;
- shared canonical identity;
- shared engagement/intelligence;
- `concierge_summit` profile on the same orchestrator/tool contracts.

Preserve device/session/privacy behavior.

---

## J5. `mindagent-bootstrap`

### Classification
**KEEP/EVOLVE — P1 Concierge**

Likely remains an app-safe bootstrap endpoint using `api` contracts. Ensure it consumes canonical data after migration.

---

## J6. `treble-find-location`

### Classification
**KEEP/EVOLVE — P1 Concierge/WhatsApp**

Can become a semantic tool over Summit navigation data.

---

## J7. `mindagent-admin`

### Classification
**KEEP/EVOLVE — P2**

Admin backend remains useful, but data targets/editorial workflow must migrate to canonical domains and retain audit/security controls.

---

## J8. `mindagent-sync-precos`

### Classification
**EVOLVE — P1 Commercial**

Sync target must become `commercial` rather than Summit-local offer state. Preserve provider/API behavior and idempotency.

---

## J9. `treble-api`

### Classification
**KEEP/EVOLVE ADAPTER — P1**

Review exact consumers before changing. Channel/integration endpoints may stay thin around canonical Agent API/core.

---

## J10. `treble-agent` v4

### Current
Abandoned predecessor recovered from production checkpoint.

### Classification
**RETIRE — P3**

Only after confirming no webhook/consumer calls it. Archive remains in checkpoint.

---

# PART K — INTEGRATIONS AND EXTERNAL SYSTEMS

## K1. HubSpot

### Current
`crm.pessoas` described as HubSpot read mirror; sync state/product mappings exist.

### Target
- HubSpot likely authority for owner/pipeline/stage if confirmed by operations.
- canonical person remains `people.people`.
- agent intelligence lives in Supabase.
- external IDs in `integrations.external_refs`.
- sync lifecycle in `integrations.sync_*`.

### Classification
**EVOLVE — P1/P2**

Final authority decision remains open and must be closed in Source of Truth.

---

## K2. `crm.sync_estado`

### Classification
**MOVE — P1/P2**

Target: `integrations.sync_state`.

---

## K3. `crm.mapa_produtos`

### Classification
**MOVE/EVOLVE — P1/P2**

Target: `integrations.value_mappings` referencing canonical product/product run.

---

## K4. Treble external conversation/session IDs

### Classification
**MOVE — P1**

Treble is transport/channel authority for its session ids. Store as external refs/metadata linked to canonical engagement conversation.

Treble session id must not be canonical person identity.

---

## K5. Eduzz/payment provider

### Classification
**NEW/EVOLVE — P2**

Provider events should populate normalized orders/payments/refunds/access rights with provenance. Buyer/payer/participant roles must remain distinct.

---

# PART L — OPS, ADMIN, AUDIT AND EVALS

## L1. `treble.agent_events`

### Current
Webhook/event idempotency processing state.

### Classification
**MOVE — P1**

Target: `integrations.webhook_events` and/or `ops.idempotency_keys`.

Preserve request/event key, attempts, status, error and timestamps.

---

## L2. `public.mind_admin_audit` + `concierge.config_auditoria` + other access logs

### Classification
**MERGE/EVOLVE — P2**

Target: coherent `ops.audit_log`, possibly retaining security/privacy-specific audit detail where required.

---

## L3. `public.mind_admin_users`

### Classification
**KEEP/EVOLVE — P2**

Admin authorization is a distinct application concern. Keep server-side authorization source; do not derive permissions from user-editable metadata.

---

## L4. `public.mind_admin_editorial`

### Classification
**KEEP/EVOLVE — P2**

Editorial sidecar may remain if it cleanly governs canonical resource publication states. Repoint resources after people/sessions migration.

---

## L5. `public.mind_admin_event_details`

### Classification
**MOVE/EVOLVE — P2**

Fields should move to owning canonical event/edition model if they are true event attributes. Keep sidecar only for admin-only workflow semantics.

---

# PART M — SECURITY AND RECOVERY BLOCKERS

## M1. RLS disabled on 12 current tables

Supabase currently reports RLS disabled on:
- `catalogo.produtos`
- `catalogo.produto_componentes`
- `engagement.identidades`
- `engagement.pessoa_perfil`
- `summit.knowledge_documents`
- `summit.knowledge_chunks`
- `institute.knowledge_documents`
- `institute.knowledge_chunks`
- `dash.knowledge_documents`
- `dash.knowledge_chunks`
- `eventos.knowledge_documents`
- `eventos.knowledge_chunks`

### Classification
**P0 SECURITY**

Do not simply enable RLS without policies; that could break consumers. For each table, determine:
- exposed schema status;
- current browser/app consumers;
- service-role consumers;
- required read/write roles;
- migration timing.

Target rule: any table exposed through Data API must have appropriate RLS and authorization policy.

---

## M2. SECURITY DEFINER / search_path / public functions

Previously observed advisor warnings include:
- mutable search_path;
- public extensions;
- SECURITY DEFINER functions executable by broad roles;
- cron anonymous policies;
- leaked-password protection disabled.

### Classification
**P0/P1 SECURITY HARDENING**

Review individually before go-live; do not apply blind blanket fixes during domain migration.

---

## M3. Missing schema dump

### Current checkpoint gap
`database-schema.sql` was not captured.

### Classification
**P0 RECOVERY**

Migration plan must obtain a reliable structural baseline or equivalent reproducible schema representation before destructive cleanup.

---

## M4. 71 applied migrations without repo files

### Current
99 applied migrations; 33 files in repo; 71 applied migrations lack corresponding files according to checkpoint reconciliation.

### Classification
**P0 RECOVERY / SOURCE-OF-TRUTH DRIFT**

Before destructive migration:
- recover statements to an archive/baseline where possible;
- record that historical replay may not be identical until baseline strategy is established;
- establish one clean future migration chain from the reconciled baseline.

Do not pretend current Git history fully reproduces production.

---

## M5. Curated configuration outside migrations

Must preserve before any destructive migration:
- `treble.prompts`
- `treble.config`
- `summit.commercial_rules`
- `summit.offers`
- `engagement.origens`
- `crm.mapa_produtos`
- Concierge prompts/config/tools/templates/flags where relevant

### Classification
**P0 DATA/CONFIG PRESERVATION**

Export/seed/version non-secret configuration in the migration program.

Secrets must move/remain in secret manager, not be exported to Git.

---

## M6. `mind-assets` bucket

### Current checkpoint gap
Bucket not included in checkpoint.

### Classification
**P1/P2 RECOVERY**

Inventory and back up before any storage reorganization. Later map speaker assets to target Storage convention (`people-assets` etc.) without breaking public URLs unexpectedly.

---

# PART N — HIGH-VALUE BEHAVIOR TO PRESERVE EXACTLY

Architecture migration must not regress these working behaviors.

## Sales/Treble
- webhook validation;
- event dedup/idempotency;
- UTM/origin capture;
- product context;
- official price retrieval;
- price hallucination guardrail;
- group/volume calculation logic;
- lot/current-moment logic;
- checkout attribution;
- structured audience/intent/interest/objection/stage output;
- handoff signal;
- recent-message dedup.

## Concierge/App
- authenticated session validation;
- device/session continuity;
- identity binding;
- profile/history loading;
- privacy-aware handling;
- official context retrieval;
- message persistence;
- personalized recommendation context;
- interest/memory evidence patterns;
- event navigation/agenda capability.

## Cross-cutting
- real Summit agenda and speaker data;
- curated product/commercial configuration;
- source/UTM attribution;
- current admin/editorial audit behavior where useful.

These become migration acceptance tests, not optional nice-to-haves.

---

# PART O — PROPOSED MIGRATION WAVES (LOGICAL, NOT YET EXECUTION PLAN)

This section sets dependency direction only. Exact migrations/backfills/compatibility are defined in `16_MIGRATION_PLAN.md`.

## Wave 0 — Recovery + safety baseline
- recover/baseline missing schema/migrations;
- export curated config;
- inventory storage/secrets/consumers;
- security exposure map;
- no destructive changes.

## Wave 1 — Canonical identity + catalog foundations
- target schema additions discovered above;
- `people` canonical identity/contact points/external refs;
- `catalog` products/product runs/product components;
- compatibility aliases/views where needed.

## Wave 2 — Summit + commercial canonicalization
- Summit edition → product run;
- speaker → people;
- offers/prices/discounts → commercial;
- keep old Sales contracts working through compatibility functions.

## Wave 3 — Shared engagement + intelligence
- canonical conversations/messages;
- Treble history/state migration;
- current Concierge history preserved;
- entry contexts;
- facts/insights/intents/summaries.

## Wave 4 — Agent API + Sales Summit cutover
- semantic contracts;
- Sales Behavior Spec + golden evals;
- shared orchestrator/runtime;
- Treble adapter cutover;
- verify behavior/price/context/memory before legacy retirement.

## Wave 5 — Concierge cutover
- same core identity/engagement/intelligence;
- agenda/navigation/reservation/feedback tools;
- app ingress/session retained;
- cross-channel continuity acceptance test.

## Wave 6 — Outbound foundation
- privacy/contactability/suppression complete;
- trigger/eligibility/workflow state;
- external effects idempotent/audited.

## Wave 7 — CS/Support/Researcher + broader products
- service domain;
- researcher;
- Institute/Dash/Events product-specific depth.

## Wave 8 — Legacy retirement and hardening
- remove compatibility RPCs/tables/functions only after usage verification;
- complete security hardening;
- consolidate observability/evals;
- clean archived prototype objects.

---

# PART P — OPEN DECISIONS REQUIRED BEFORE FINAL MIGRATION PLAN

1. Confirm HubSpot authority for owner/pipeline/stage.
2. Confirm authoritative commerce/payment systems by product/run.
3. Confirm attendee/access authority and reconciliation rules (Eduzz/Yazo/manual/invite/upgrade).
4. Decide final physical names for target additions:
   - people.identity_merges
   - catalog.product_components
   - commercial.discount_codes
   - engagement.entry_points
   - privacy.data_requests
   - integrations.value_mappings
5. Confirm whether current `summit.locations` remains the physical name instead of renaming to `spaces` (recommended: keep).
6. Confirm which current Summit features remain in 2026 Concierge scope: polls, exhibitors, navigation, networking.
7. Establish structural baseline strategy for the 71 missing migration files.
8. Export/version curated configuration before first destructive operation.
9. Inventory actual consumers of public/API RPCs and Edge Functions before deprecation.
10. Define dev/staging/prod migration path before target writes begin.

---

# PART Q — FIRST VERTICAL ACCEPTANCE TEST

Sales Summit target is not accepted merely because the schema migrates.

Minimum behavioral continuity scenario:

### Conversation 1
User says:
> “Oi, sou Adriana, trabalho na Empresa X. Queria saber mais sobre o VIP.”

System must:
- resolve/create one canonical person;
- preserve Company X as evidence/context without inventing verification;
- detect VIP interest;
- identify Sales intent;
- answer with current authoritative Summit/commercial context;
- store conversation/message in shared engagement;
- create appropriate intelligence evidence.

### Conversation 2 — later
User says:
> “Oi, voltei. Minha preocupação é que dois dias fora é muito.”

System must know, without re-asking:
- same person;
- company context;
- prior VIP evaluation;
- prior conversation summary/history;
- new time objection;
- current Summit context and current offer/pricing state.

It must respond according to Sales Behavior Spec, not restart qualification.

This scenario becomes one of the executable golden evals and an end-to-end migration acceptance test.

---

# FINAL RECONCILIATION STATEMENT

The current prototype contains a substantial amount of valuable business logic and product data. The migration should therefore be **surgical rather than destructive**.

The target architecture remains valid, with the adjustments identified in Part A. The most important structural convergence is:

```text
crm.pessoas + engagement.identidades
        → people + contact_points + external_refs + crm.contacts

catalogo.produtos
        → catalog.products + catalog.product_runs

treble conversations/messages
        + engagement conversations/messages
        → shared engagement core

participant memory/interests/signals
        → facts + insights + intents + summaries

summit offers/coupons/commercial rules
        → commercial

comum/product-line knowledge duplicates
        → governed knowledge + product scopes

treble/concierge prompts + tools
        → playbooks + agents + decisioning + Agent API
```

No destructive migration should begin until the P0 recovery/config/security items are incorporated into the executable migration plan.