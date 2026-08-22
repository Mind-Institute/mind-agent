# MIND INTELLIGENCE — TARGET ARCHITECTURE

## Purpose

Mind Intelligence is a shared intelligence and agent runtime for multiple Mind products and experiences. It must support Sales, Concierge, Customer Success, Support, Researcher and future product-line agents without duplicating core entities or building isolated databases per agent.

## Core flow

DATA -> INTELLIGENCE -> PLAYBOOK -> DECISIONING -> AGENT -> ACTION -> MEMORY LOOP

### Intelligence
What do we know about the person, relationship, company, situation and product fit?

### Playbook
How should an excellent professional reason and behave in this domain?

### Decisioning
What is the best move now, given the current situation, policies and playbook?

### Agent
How should that decision be executed conversationally or through tools/actions?

## Context engineering

Agents do not know the physical topology of Supabase.

The runtime provides:
- Base Context: small, essential, almost always loaded;
- Context Planner: identifies what else is needed for the current turn;
- just-in-time semantic retrieval;
- deep memory only when required;
- deep research only when required.

The primary interface to data is a semantic Agent API, not arbitrary SQL.

## Shared schemas

### catalog
- product_families
- products
- product_runs
- product_content

### people
- people
- profiles
- assets
- links
- works
- organizations
- affiliations
- product_roles
- user_accounts if required by implementation

### crm
- contacts
- companies
- deals
- tickets
- tasks
- owners
- pipelines
- pipeline_stages

### commercial
- offers
- pricing_periods
- offer_prices
- offer_inclusions
- discount_rules
- orders
- order_items
- order_people
- payments
- refunds
- access_rights

### engagement
- conversations
- entry_contexts
- messages
- message_attachments
- interactions

### intelligence
- facts
- insights
- intents
- product_fit
- summaries

### knowledge
- concepts
- concept_aliases
- sources
- claims
- claim_sources
- documents
- document_chunks
- product_concepts
- person_concepts

### service
- customer_relationships
- support_cases
- success_goals
- health_snapshots
- milestones
- satisfaction
- handoffs

### playbooks
- playbooks
- stages
- principles
- moves
- objection_types
- objection_strategies
- guardrails
- examples

### decisioning
- policies
- decisions
- next_actions

### agents
- registry
- profiles
- capabilities
- profile_capabilities
- context_profiles
- knowledge_scopes
- action_scopes
- tool_registry
- profile_tools
- delegation_rules
- prompt_versions
- runs
- tasks
- actions

### integrations
- external_refs
- webhook_events
- sync_runs
- sync_state
- sync_errors

### ops
- domain_events
- outbox_events
- audit_log
- idempotency_keys

### evals
- datasets
- cases
- expected_behaviors
- runs
- scores
- failures
- human_feedback

### agent_api
No business tables. Contains semantic Database Functions/RPC contracts exposed to agent runtimes.

## Product-specific schemas

### summit
- editions
- venues
- spaces
- edition_people
- sessions
- session_people
- session_concepts
- materials
- reservations
- attendance
- feedback
- v_agenda

### institute
- programs
- cohorts
- modules
- lessons
- live_sessions
- faculty
- program_concepts
- module_concepts
- materials
- enrollments
- completions
- credentials
- credential_requirements
- credential_awards

### events
- editions
- guests
- sessions
- materials
- attendance
- feedback

### dash
- solutions
- use_cases
- methodologies
- deliverables
- client_engagements
- engagement_deliverables

## Product model

`catalog.products` stores canonical product identity.

Examples:
- Mind Summit
- Formação Estratégica em Bem-Estar no Trabalho e Liderança Positiva
- Significado no Trabalho
- Segurança Psicológica
- Mind Journey
- On Demand
- Oxford no Conselho
- Mind Dash

`catalog.product_runs` stores concrete delivery instances.

Examples:
- Mind Summit 2026
- Mind Summit 2025
- Formação A / turma 2025
- Journey / entrega 2025

A product run is the universal concrete key used by CRM, commercial, engagement, intelligence, playbooks and product-specific facets.

Example:

Mind Summit 2026 = `catalog.product_runs.id = X`

Then:
- `summit.editions.product_run_id = X`
- `commercial.offers.product_run_id = X`
- `crm.deals.product_run_id = X`
- `intelligence.product_fit.product_run_id = X`
- `engagement.conversations.product_run_id = X`
- `playbooks.playbooks.product_run_id = X`

There are not multiple independent copies of Mind Summit 2026.

## Person model

`people.people` is canonical identity.

The same person may be:
- Summit speaker;
- Institute faculty;
- author;
- advisor;
- customer;
- lead;
- participant.

Contextual roles must not create duplicate person rows.

`crm.contacts` represents the commercial relationship with Mind.

Profiles, works, organizations and affiliations belong to the global person model.

## Agent runtime

A base runtime supports profiles rather than separate hard-coded systems per product.

Initial profiles:
- sales_summit
- concierge_summit
- service_default
- researcher_scientific

A profile combines:
- base agent;
- product scope;
- context profile;
- playbook;
- capabilities;
- knowledge scopes;
- action scopes;
- tools;
- permissions.

Visible conversation persona may stay the same even when background workers or specialist profiles are delegated.

## Turn pipeline

Synchronous path:
1. webhook/request arrives;
2. idempotency/dedup;
3. persist raw message;
4. resolve person;
5. triage intent/product/capability/profile;
6. build Base Context;
7. Context Planner identifies missing context;
8. retrieve just-in-time through Agent API;
9. combine Intelligence + Playbook + Policies;
10. Decisioning selects move/next action;
11. Agent responds/uses tool/delegates/acts;
12. persist run, decision, response and actions.

Background path:
- extract turn intelligence;
- consolidate facts;
- update summaries;
- recalculate fit;
- sync external systems;
- evaluate opportunity/follow-up;
- generate embeddings;
- process queued actions.

Do not force multiple LLM calls synchronously when one call can safely return structured decision + response.

## Agent API principles

Preferred semantic contracts include:
- build_base_context()
- get_person_context()
- get_relationship_context()
- get_conversation_context()
- get_product_context()
- get_commercial_context()
- get_service_context()
- get_relevant_product_content()
- get_relevant_knowledge()
- get_effective_playbook()
- search_deep_knowledge()
- search_person_history()
- find_summit_sessions()
- compare_offers()
- get_current_price()
- record_fact()
- record_insight()
- record_intent()
- update_summary()
- record_product_fit()
- get_applicable_policies()
- record_decision()
- get_next_best_actions()
- create_followup()
- create_ticket()
- create_crm_task()
- update_crm()
- delegate_task()
- handoff_to_human()
- request_deep_research()

## Key invariant

The agent should never need to know where a fact is physically stored.

A stable logical contract can internally join different schemas depending on product family.

## Migration principle

Current working logic should be reused when sound, but current table placement is not a constraint.

The current system is a prototype. We preserve good behavior and data, not accidental topology.