# MIND INTELLIGENCE — PHASE 0D OPEN DECISIONS

Status: OPEN DECISION REGISTER

Purpose: prevent implementation from silently answering business/source-of-truth questions that are not purely technical.

## Decision 1 — HubSpot authority
Question: Is HubSpot the operational source of truth for owner, pipeline and stage?

Default assumption for planning: **yes**, until operations explicitly says otherwise.

Supabase stores the canonical person plus agent intelligence/context. HubSpot may remain operational authority for sales ownership/stage.

## Decision 2 — Commerce/payment authority by product
Question: Which provider is authoritative for order/payment/refund status for each product/run?

Current likely provider for relevant Summit flows: Eduzz.

Do not infer payment truth from CRM labels when provider transaction state is available.

## Decision 3 — Attendee/access authority
Question: How should entitlement be reconciled across purchase, invited participant, manual upgrade, event-platform registration and operational exceptions?

Target principle: `commercial.access_rights` is the normalized authority, derived only from verified source events/rules.

The reconciliation rule still needs explicit specification before full access migration.

## Decision 4 — Editorial authority
Question: Which product copy, bios and agenda fields are edited in Supabase/admin vs external CMS/platforms?

Target principle: every field must have one declared authority; website presence alone does not make the website authority for all data.

## Decision 5 — Environments
Question: What exact dev/staging/prod Supabase setup will be used for Vibe Code?

This must be closed before Wave 1 implementation. Production cannot be the coding-agent sandbox.

## Decision 6 — 71 missing migration statements
Question: What baseline strategy will make future schema reproducible despite incomplete historical migration files?

Recommended direction:
- archive recoverable historical statements;
- capture a trusted current structural baseline;
- start a clean forward migration chain from that baseline;
- do not attempt to beautify/replay three days of prototype history as if it were a mature historical chain.

## Decision 7 — Current Summit feature scope
Confirm whether these are required for Summit 2026 Concierge launch:
- polls;
- exhibitors;
- route/navigation;
- networking/contact requests.

Navigation is currently considered likely required. Others can be preserved without necessarily being launch-blocking.

## Decision 8 — Physical privacy schema
Default recommendation: use `privacy` as the physical schema for consents/contactability/suppressions/data_requests.

## Decision 9 — `summit.locations` name
Recommendation: keep current physical name `summit.locations`; do not rename to `spaces` without semantic reason.

## Decision 10 — First implementation authorization
No target schema implementation is authorized yet.

The first coding-agent task after Phase 0D should be a Wave 0 safety/recovery/environment task, not a `people.people` migration.