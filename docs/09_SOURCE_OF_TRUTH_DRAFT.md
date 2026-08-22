# MIND INTELLIGENCE — SOURCE OF TRUTH (DRAFT)

Status: DRAFT até fechamento do checkpoint reconciliation e current-to-target map.

Este documento define qual sistema/domínio é autoridade por tipo de dado. Não confundir “quem possui uma cópia” com “quem é fonte de verdade”.

## Principles

1. Um dado pode aparecer em vários sistemas, mas deve existir uma autoridade clara.
2. Agents consultam contracts semânticos; não precisam saber qual sistema é autoridade física.
3. Sync não transforma réplica em fonte de verdade.
4. Mudança de autoridade exige ADR/migration plan.
5. Inference de IA nunca sobrepõe silently verified fact.
6. Generic document/vector retrieval nunca sobrepõe structured operational authority.

## Proposed authority matrix

### Canonical person identity
Authority target: `people.people`.

External systems such as HubSpot, Treble, Eduzz and app/Yazo keep external ids/attributes mapped via `integrations.external_refs`.

### Human contact points
Authority target: `people.contact_points` for normalized email/phone/contact identifiers used by Mind.

Provider-specific IDs are not contact points; they belong to `integrations.external_refs`.

### Consent / contactability / suppression
Authority target: dedicated privacy/contactability domain in Supabase, fed by explicit user events, channel/provider events and operational rules.

Outbound send decision must use this domain deterministically. LLM recommendation is never authority for whether contact is allowed.

### Person professional/public profile
Authority target: `people.profiles`, `people.works`, `people.affiliations`, `people.assets` for curated Mind data.

External source provenance should be retained where relevant.

### CRM owner / pipeline / stage
Proposed authority: HubSpot for operational sales ownership/stage, mirrored into Supabase where agent context needs it.

This must be validated against actual operating process before finalization.

### CRM relationship enrichment / agent intelligence
Authority target: Supabase (`crm` + `intelligence`).

Agent-generated insights should not overwrite authoritative HubSpot fields unless an explicit sync policy exists.

### Product catalog
Authority target: Supabase `catalog`.

### Product run/edition/cohort identity
Authority target: Supabase `catalog.product_runs` plus product-specific facet.

### Summit agenda / sessions / speakers / spaces
Authority target: Supabase Summit/People curated operational data.

If another scheduling platform becomes the true operational authority, sync policy must be documented.

### Offer / price / lot / discount rule
Authority target: Supabase `commercial`.

Prompts and vector/document retrieval are never authority.
Checkout/platform values may be synchronized but must not silently diverge.

### Orders / payment events
Likely originating authority: payment/commerce provider (currently Eduzz for relevant flows) for transaction status; normalized canonical representation in `commercial.orders/payments/refunds`.

Exact conflict resolution to be specified during integration design.

### Access rights
Authority target: derived/canonical `commercial.access_rights`, based on verified transaction/invite/upgrade sources.

### Conversation/message history
Authority target: Supabase `engagement` for agent-visible normalized history, while channel provider remains transport source.

A person may have multiple conversations by channel. Relationship continuity lives above the individual conversation.

Raw webhook event can be preserved separately in `integrations.webhook_events`.

### Entry source / UTM / attribution
Authority target: captured first-party event/session context in Supabase engagement/integrations, with original values retained.

### Intelligence facts/insights/intents/summaries/fit
Authority target: Supabase `intelligence`.

However, `intelligence.facts` must not duplicate stronger canonical domains such as contact points, purchases, prices or affiliations merely for convenience.

### Scientific knowledge
Authority target: Supabase `knowledge` as curated structured representation; original external papers/books/reports remain provenance/source artifacts.

Scientific claim authority must preserve source/caveat/review status where relevant.

### Product copy / FAQ / positioning
Authority target: Supabase `catalog.product_content` or explicitly designated editorial CMS if future architecture changes.

### Website
The website is a source, not automatically authority for every field it contains.

Each ingested field must respect domain authority. Example: a website page may be authoritative for approved positioning but should not overwrite transactional payment state.

### Playbooks / policies / agent profiles
Authority target: Supabase/configuration versioned in repository/migrations as defined during implementation.

### Sales behavior specification
Authority target: versioned repository document `docs/11_SALES_AGENT_BEHAVIOR_SPEC.md`, later paired with executable golden evals.

Prompt/playbook implementation must conform to this behavior spec rather than redefining it silently.

### Agent prompt versions
Authority target: versioned prompt/config layer (`agents.prompt_versions`) with clear deployment path. Repository should preserve source/history.

### Evals / expected behaviors
Authority target: versioned repository/evals dataset and normalized eval records in Supabase when implemented.

Golden expectations must not be casually rewritten to fit a failing implementation.

### Runtime code
Authority: Git repository.

Published Edge Functions must correspond to versioned code; production-only unversioned code is considered drift and must be eliminated.

### Database schema
Authority: versioned schema/migrations in Git, not manual Dashboard state.

Production DB is runtime state, but its structure should be reproducible from version control.

Current exception/risk: 71 applied migrations are known without corresponding repo files and the structural dump is still missing. This must be reconciled before destructive migration.

### Secrets
Authority: environment/secret manager; never repository or database content tables unless explicitly secure design requires it.

### Agent run observability
Authority target: run/trace records in Supabase linked to versioned code/config.

Operationally relevant reconstruction should include model, prompt, playbook, context profile, tools/results and context/retrieval trace without chain-of-thought.

## Conflict rules — draft

When a mismatch appears:
- authoritative system wins;
- discrepancy is logged;
- do not silently merge fields with incompatible semantics;
- identity conflicts require explicit merge workflow;
- transactional state must preserve provider event provenance;
- agent inference cannot override verified fact;
- stale document content cannot override current structured operational state;
- suppression/contactability negative result blocks outbound even if an agent recommends send.

## Items to validate before FINAL

- Is HubSpot definitively authority for owner/stage/pipeline?
- Which checkout/payment platform(s) are authoritative by product?
- Whether attendee/access authority is Eduzz, app import, manual operations, or derived combination.
- Which editorial fields remain maintained externally vs Supabase.
- Final sync frequency/event strategy for HubSpot.
- Whether Treble conversation id remains only external_ref after unified engagement migration.
- Final physical schema/name for privacy/contactability/suppression.
- Recovery strategy for 71 applied migrations without files.
- Capture/migration of curated config currently outside migrations.

Update this file after checkpoint/current-to-target review and remove DRAFT marker only after explicit approval.