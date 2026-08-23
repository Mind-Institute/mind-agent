# MIND INTELLIGENCE — LEGACY REUSE AND MIGRATION POLICY

Status: AUTHORITATIVE EXECUTION DECISION — 2026-08-22

## Purpose

Define how the existing Supabase/GitHub prototype is used while implementing the frozen Mind Intelligence target architecture.

This policy does **not** change the target architecture or the phase order already defined in the repository. It changes the assumption that existing data/config/content should be bulk-preserved or bulk-migrated before target implementation.

## Authoritative business decision

The current legacy is a prototype and is **not trusted by default**.

- Existence in the database does not make content correct, approved, current, or worth migrating.
- AI-generated prompts, playbooks, templates, configs, rules, summaries, classifications, recommendations, memories, or commercial content are not Mind source of truth unless Adriana explicitly validates them.
- Concierge interaction data currently in the system is test data and is not a target backfill requirement.
- Commercial behavior/content currently stored in the prototype must be reviewed before reuse; it must not be promoted automatically into Playbook, Decisioning, Intelligence, Knowledge, or Source of Truth.

## Migration rule: just-in-time legacy review

Do **not** perform broad content/config migration up front.

When a target object is being implemented, inspect the semantically corresponding legacy object at that moment and classify it as exactly one of:

1. **REUSE** — trustworthy operational data/behavior can be copied or mapped with validation.
2. **TRANSFORM** — useful information exists but must be normalized/restructured and validated.
3. **REBUILD** — the target capability should be created from approved requirements rather than legacy content.
4. **DISCARD** — test, obsolete, untrusted, duplicated, or low-value legacy content does not enter the target.

Record the decision in the implementation PR/migration notes for that object.

## What may be reused without treating it as business truth

Operational facts may be reused when independently validated and required for continuity, including examples such as:

- stable identifiers and external references;
- current product/event identifiers;
- current authoritative price/lot/checkout outputs;
- session/speaker/agenda records that match the official event source;
- UTM/origin mappings;
- webhook contracts, idempotency behavior, and integration identifiers;
- technical mappings required to avoid breaking live consumers.

Operational reuse still requires deterministic comparison where correctness matters.

## What is not a preservation blocker

The following do not need bulk export/backfill before target work:

- Concierge test conversations/messages and intelligence derived from them;
- AI-generated prompts/playbooks/templates/configuration not explicitly approved;
- experimental recommendation weights, classifications, rules, summaries, dossiers, or memories;
- prototype commercial arguments/objection handling not explicitly validated;
- prototype content that can remain in the legacy system until the corresponding target object is implemented.

## What must still be protected

We still protect what can break production or make rollback impossible:

- migration history / structural recovery sufficient for safe change;
- live integration contracts and consumers touched by a change;
- secrets by dependency/name (never commit secret values);
- operational data actually required by the target cutover;
- safe dev/staging path before target production migration;
- security/RLS implications for objects being changed.

## Implementation principle

**Build the frozen target architecture. Consult legacy just in time. Migrate only what earns its way into the target.**

Do not redesign target objects around prototype topology merely to preserve legacy.
Do not discard a live dependency without consumer verification.
Do not promote unvalidated legacy content into business truth.

## Sales-specific implication

The Sales Summit target must be built from the approved Sales Behavior Spec, approved business decisions, and validated authoritative operational facts.

Legacy Sales/Treble content can be inspected as reference during implementation, but no commercial behavior becomes target Playbook/Decisioning/Knowledge merely because it already exists.

## Conflict rule

If an older planning document can be read as requiring blanket preservation/migration of untrusted prototype content, this policy controls the interpretation: preservation means **avoid irreversible loss before an object-level decision**, not **migrate everything into the target**.
