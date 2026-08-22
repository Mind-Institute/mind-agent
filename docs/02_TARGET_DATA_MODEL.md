# MIND INTELLIGENCE — TARGET DATA MODEL

Este documento descreve a arquitetura de dados target. É normativo para novas migrations e refactors.

## Shared schemas

### catalog
- product_families
- products
- product_runs
- product_content

`product_families`: id, slug, name, description, status, timestamps.

`products`: id, family_id, parent_product_id nullable, name, slug, product_type, status, short_description, timestamps.

`product_runs`: id, product_id, run_type, name, year, sales_start_at, sales_end_at, delivery_start_at, delivery_end_at, status, timestamps.

`product_content`: id, product_id, product_run_id nullable, content_type, title, body, locale, priority, valid_from, valid_until, status, timestamps.

Content types iniciais: description, audience, value_proposition, differentiator, outcome, feature, proof_point, faq, case, use_case.

### people
- people
- profiles
- assets
- links
- works
- organizations
- affiliations
- product_roles

`people.people` é identidade canônica. Não guardar cópias por papel/canal.

`profiles`: profile_type, locale, headline, mini_bio, short_bio, long_bio, optional product/product_run override, validity/status.

`assets`: referências a Storage; não guardar binários no banco.

`works`: book, paper, article, podcast, course, report, other; title/year/publisher/url/isbn/doi; optional knowledge_source_id.

`organizations` + `affiliations`: vínculos institucionais globais, distintos de CRM companies.

`product_roles`: pessoa ↔ product/product_run com papel contextual.

### crm
- contacts
- companies
- deals
- tickets
- tasks
- owners
- pipelines
- pipeline_stages

`crm.contacts` referencia `people.people` e representa a relação comercial.

`crm.companies` pode referenciar uma organização global.

`crm.deals`: person/contact/company/product/product_run/offer/pipeline/stage/amount/owner/status conforme necessidade real.

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

Oferta comercial é separada da identidade do produto.

Exemplo: Summit 2026 run → offers MIND / VIP / PRIME / Corporate.

`pricing_periods`: lotes/janelas de preço.
`offer_prices`: offer + pricing period + amount/currency/validity.
`offer_inclusions`: acesso/benefícios.
`discount_rules`: regras e guardrails de desconto/volume.
`order_people`: role buyer/payer/participant/beneficiary para resolver comprador ≠ participante.
`access_rights`: direitos de acesso derivados da compra/condição.

### engagement
- conversations
- entry_contexts
- messages
- message_attachments
- interactions

`conversations`: person/channel/product scope/start/last/close/status.

`entry_contexts`: source, campaign, landing page, referrer, entry point, product/product_run/offer hints, intent_hint, metadata.

Entry context é crítico para Treble. A pessoa que chega por PRIME abandonado e a que chega por “leve sua empresa” não devem receber a mesma pergunta inicial quando o contexto já é conhecido.

`messages`: raw messages; sender customer/human/agent/system; visible_agent/profile quando aplicável; agent_run_id; content/timestamps.

`interactions`: timeline não textual: page_view, form_submit, click, download, reserved, attended, meeting, purchase, refund, feedback, email_open etc.

### intelligence
- facts
- insights
- intents
- product_fit
- summaries

Não criar tabela separada para dor, desejo, objeção e interesse.

`facts`: fatos objetivamente conhecidos; key/value_json; source; verification status; validity.

`insights`: person/org, insight_type, value_text/value_json, confidence, source_type/source_id, status, validity, supersedes_id, created_by_agent_id.

Insight types iniciais: pain, need, desire, goal, interest, preference, objection, constraint, decision_criterion, buying_signal, risk.

`intents`: transient routing signals; person/conversation/message, intent_type, product scope, confidence/status/time.

Intent examples: sales_b2b, sales_b2c, support, research, event_navigation, product_information, complaint, feedback.

`product_fit`: person/product/product_run, fit_score, intent_score, potential_tier, reason_summary, evidence_json, calculated_at.

`summaries`: relationship/commercial/product-specific summaries com valid_through_at e generated_by.

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

`concepts`: psychological safety, burnout, wellbeing at work, meaning, leadership, job design, resilience etc. Pode ter parent concept.

`concept_aliases`: aliases/traduções.

`claims`: afirmações científicas estruturadas com evidence_strength, caveat e status.

`sources`: papers/books/reports/original sources.

`claim_sources`: many-to-many claim ↔ source.

`documents`: original/curated content com storage path/content/version/validity.

`document_chunks`: chunks + embeddings (pgvector), quando necessário.

`product_concepts`, `person_concepts`: relações semânticas.

### service
- customer_relationships
- support_cases
- success_goals
- health_snapshots
- milestones
- satisfaction
- handoffs

Service é compartilhado por Support e Customer Success.

### playbooks
- playbooks
- stages
- principles
- moves
- objection_types
- objection_strategies
- guardrails
- examples

Playbooks inicialmente são dados/configuração, não lógica hard-coded.

Herança esperada:
Sales Core → Summit Sales → Summit 2026 overlay.
Outras linhas herdam Sales Core conforme aplicável.

### decisioning
- policies
- decisions
- next_actions

`policies`: regras duras, por exemplo limite de desconto, suporte crítico precisa de humano, claim científico de alto risco exige Researcher.

`decisions`: conversation/agent_run/current_stage/objective/selected_move/next_best_action/confidence/rationale_summary.

Guardar rationale operacional suficiente para auditoria; não armazenar chain-of-thought privada.

`next_actions`: person/deal/action_type/priority/reason/status/due_at/created_by.

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

Base agents sugeridos: router, sales, concierge, service, researcher, recommendation_worker, crm_worker, opportunity_worker.

Profiles iniciais: sales_summit, concierge_summit, service_default, researcher_scientific.

### integrations
- external_refs
- webhook_events
- sync_runs
- sync_state
- sync_errors

`external_refs`: internal entity/id ↔ provider/external_id para HubSpot, Treble, Eduzz, LearnWorlds, site etc.

`webhook_events`: payload bruto + external event id + idempotency/status/error/replay/debug.

### ops
- domain_events
- outbox_events
- audit_log
- idempotency_keys

Transactional outbox é o padrão desejado para efeitos externos críticos.

### evals
- datasets
- cases
- expected_behaviors
- runs
- scores
- failures
- human_feedback

### agent_api
Sem tabelas de negócio. Apenas functions/RPCs/views seguras que apresentam contratos semânticos estáveis aos agents.

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
- v_agenda (VIEW)

`summit.editions.product_run_id` deve ser UNIQUE FK para `catalog.product_runs`.

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

`programs.product_id` deve representar produto canônico; cohorts referem product_run.

Credential rules são versionáveis/configuráveis. Em 2025, a combinação das formações podia gerar uma credencial; isso não transforma a credencial em produto independente por padrão.

### events
- editions
- guests
- sessions
- materials
- attendance
- feedback

Manter simples; não criar `event_core` genérico prematuramente.

### dash
- solutions
- use_cases
- methodologies
- deliverables
- client_engagements
- engagement_deliverables

## Other Supabase surfaces

### api
Custom schema opcional para views/RPCs seguras consumidas por browser/app.

### auth
Supabase native Auth.

### Storage buckets previstos
- people-assets
- product-assets
- knowledge-documents
- private-attachments

## Invariants

1. Canonical person existe uma vez.
2. Canonical product existe uma vez.
3. Product run é a chave concreta universal para edição/cohort/delivery/version.
4. Product-specific schemas são facets, não novas identidades.
5. Dados inferidos têm provenance/confidence.
6. Conversas são cross-channel no mesmo domínio `engagement`.
7. Oferta/preço pertencem a `commercial`, não a Summit.
8. Conhecimento científico pertence a `knowledge`.
9. Agent API esconde joins/topologia.
10. Estrutura final pode evoluir, mas mudanças nesses invariants exigem ADR.