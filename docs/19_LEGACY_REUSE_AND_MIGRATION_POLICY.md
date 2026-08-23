# MIND INTELLIGENCE — CURRENT SYSTEM REVIEW AND MIGRATION POLICY

Status: AUTHORITATIVE EXECUTION DECISION — 2026-08-22

## Purpose

Define how the existing operational Supabase/GitHub system is used while implementing the frozen Mind Intelligence target architecture.

This policy does **not** change the target architecture or the phase order already defined in the repository. It changes only the assumption that existing data/config/content should be bulk-preserved or bulk-migrated before target implementation.

## Authoritative business decision

The current system is **not disposable**. It contains live infrastructure, integrations, operational data, contracts and behaviors that may be important to continuity and must not be casually removed.

At the same time, content or business decisions stored in the current system are **not automatically trusted or approved** merely because they exist there.

- Existence in the database does not make a prompt, rule, classification, commercial argument, config value, summary or AI-generated interpretation correct, approved, current, or worth migrating.
- AI-generated prompts, playbooks, templates, configs, rules, summaries, classifications, recommendations, memories, or commercial content are not Mind source of truth unless Adriana explicitly validates them.
- Concierge interaction data currently in the system is test data and is not a target backfill requirement.
- Commercial behavior/content currently stored in the system must be reviewed before reuse; it must not be promoted automatically into Playbook, Decisioning, Intelligence, Knowledge, or Source of Truth.
- Live operational behavior and integration dependencies must be preserved until the corresponding target implementation has been validated and cut over safely.

## Migration rule: just-in-time current-system review

Do **not** perform broad content/config migration up front merely to preserve everything.

When a target object is being implemented, inspect the semantically corresponding current-system object at that moment and classify the relevant records/behavior as exactly one of:

1. **REUSE** — trustworthy operational data/behavior can be copied or mapped with validation.
2. **TRANSFORM** — useful information exists but must be normalized/restructured and validated.
3. **REBUILD** — the target capability should be created from approved requirements rather than inherited content.
4. **DO NOT MIGRATE** — specific test, obsolete, untrusted, duplicated, or low-value content does not enter the target. This does not authorize deleting the current live object before consumer/cutover verification.

Record the decision in the implementation PR/migration notes for that target object.

## What may be reused without treating it as business truth

Operational facts and contracts may be reused when validated and required for continuity, including examples such as:

- stable identifiers and external references;
- current product/event identifiers;
- current authoritative price/lot/checkout outputs;
- session/speaker/agenda records that match the official event source;
- UTM/origin mappings;
- webhook contracts, idempotency behavior, integration identifiers and live adapter behavior;
- technical mappings required to avoid breaking live consumers.

Operational reuse still requires deterministic comparison where correctness matters.

## What is not a bulk-migration blocker

The following do not need bulk export/backfill before target work solely because they exist:

- Concierge test conversations/messages and intelligence derived from them;
- AI-generated prompts/playbooks/templates/configuration not explicitly approved;
- experimental recommendation weights, classifications, rules, summaries, dossiers, or memories;
- commercial arguments/objection handling not explicitly validated;
- unreviewed content that can remain safely in the current system until the corresponding target object is implemented.

## What must still be protected

We still protect what can break production or make rollback impossible:

- migration history / structural recovery sufficient for safe change;
- live integration contracts and consumers touched by a change;
- secrets by dependency/name (never commit secret values);
- operational data actually required by the target cutover;
- safe dev/staging path before target production migration;
- security/RLS implications for objects being changed.

## Implementation principle

**Build the frozen target architecture. Inspect the current system just in time. Migrate only what is validated and useful. Preserve live continuity until cutover is proven.**

Do not redesign target objects around current topology merely to avoid making the intended architectural change.
Do not discard a live dependency without consumer verification.
Do not promote unvalidated content into business truth.
Do not delete current-system objects merely because their content will not be migrated.

## Sales-specific implication

The Sales Summit target must be built from the approved Sales Behavior Spec, approved business decisions, and validated authoritative operational facts.

Current Sales/Treble content can be inspected as reference during implementation, but no commercial behavior becomes target Playbook/Decisioning/Knowledge merely because it already exists.

## Conflict rule

If an older planning document can be read as requiring blanket preservation/migration of untrusted content, this policy controls the interpretation: preservation means **avoid irreversible loss or production breakage before an object-level decision**, not **copy every current record into the target**.
