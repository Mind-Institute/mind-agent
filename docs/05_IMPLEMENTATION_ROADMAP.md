# MIND INTELLIGENCE — IMPLEMENTATION ROADMAP

Este documento preserva a ordem macro de construção. `docs/00_EXECUTION_CONTROL.md` define qual passo está ativo AGORA.

## Fase 0A — Checkpoint do sistema existente

Objetivo: tornar o protótipo atual totalmente recuperável antes de qualquer mudança estrutural.

Definition of Done:
- branch de checkpoint;
- working tree conhecido;
- migrations preservadas;
- Edge Functions publicadas preservadas;
- snapshot estrutural do banco;
- nenhum deploy/refactor funcional.

## Fase 0B — Constituição e memória permanente

Entregáveis:
- README_FIRST.md
- CLAUDE.md
- AGENTS.md
- architecture
- project memory
- target data model
- source of truth
- security/change protocol
- agent contracts
- current state
- migration plan
- ADRs iniciais

Definition of Done:
- colaborador novo entende visão, regras e estado atual sem depender de conversa histórica;
- coding agent recebe instruções claras para não redesenhar arquitetura;
- conceitos e fronteiras de domínio estão documentados.

## Fase 0C — Plano de migração física

Comparar estado real com target.

Classificar cada estrutura:
- KEEP
- REUSE + MOVE
- REBUILD
- DELETE
- DEFER

Priorizar compatibility layer quando consumidores existentes ainda dependem de estruturas legadas.

## Fase 0D — Ambientes e guardrails

- dev/local;
- staging/preview;
- prod;
- permissions separadas;
- migrations controladas;
- secrets separados;
- checks/CI possíveis;
- RLS/security baseline.

## Fase 1 — Identity + Catalog core

Schemas:
- people
- catalog
- integrations.external_refs

Tasks:
- canonical person model;
- organizations/affiliations;
- canonical product families/products;
- product_runs;
- Summit 2026 como run;
- external id mapping.

Acceptance:
- `get_person_context` resolve pessoa de forma estável;
- Mind Summit e Summit 2026 não são duplicados;
- Treble/App conseguem apontar para mesma pessoa.

Checkpoint commit.

## Fase 2 — Summit + Commercial

Schemas:
- summit
- commercial
- people product roles
- knowledge concepts mínimo

Tasks:
- migrar/reaproveitar agenda, sessões, espaços e speakers;
- normalizar speakers para people;
- offers MIND/VIP/PRIME/Corporate;
- pricing periods/lotes;
- prices;
- discount rules;
- inclusions;
- checkout/attribution compatibility.

Acceptance:
`get_product_context(Summit 2026)` retorna produto, run, positioning relevante, people, commercial e concepts sem o agent conhecer tabelas.

Checkpoint commit.

## Fase 3 — Engagement + Intelligence + CRM relationship

Schemas:
- engagement
- intelligence
- crm core

Tasks:
- conversation model compartilhado;
- messages;
- entry_contexts;
- interactions;
- facts;
- insights;
- intents;
- summaries;
- product_fit;
- CRM contact/company/deal linkage.

Acceptance:
- pessoa inicia conversa pelo Treble;
- identidade é ligada;
- mensagens persistem;
- pessoa retorna em nova conversa e contexto anterior é recuperado.

Checkpoint commit.

## Fase 4 — Sales Summit runtime

Schemas/capabilities:
- playbooks
- decisioning
- agents
- agent_api

Tasks:
- Sales Core playbook;
- Summit Sales overlay;
- Summit 2026 overlay;
- sales_summit profile;
- Base Context;
- Context Planner V1;
- tools de produto/preço/knowledge/CRM;
- orchestrator;
- Treble adapter;
- structured decision + response;
- persist run/decision/action.

Acceptance E2E:

Conversa 1:
“Oi, sou Adriana, trabalho na Empresa X. Queria saber mais sobre o VIP.”

Expected:
- identity resolved;
- company recorded/linked;
- sales intent recorded;
- VIP interest recorded;
- correct official offer info;
- useful sales response.

Conversa 2 depois:
“Oi, voltei. Minha preocupação é que dois dias fora é muito.”

Expected:
- knows same person;
- knows company;
- knows VIP evaluation;
- identifies new objection=time;
- does not restart discovery;
- uses playbook to respond appropriately.

Checkpoint commit.

## Fase 5 — Memory loop + commercial automation

- extract-turn-intelligence;
- fact consolidation;
- refresh-summary;
- product_fit recalculation;
- evaluate-opportunity;
- HubSpot sync;
- tasks/followups;
- outbox/queues;
- retry/idempotency.

Acceptance:
- meaningful new signal changes next conversation context;
- duplicate webhook/action does not duplicate external effect;
- relevant high-fit stalled opportunity can generate follow-up/task.

## Fase 6 — Concierge Summit

Reutilizar:
- people;
- catalog;
- Summit;
- commercial/access rights;
- engagement;
- intelligence;
- knowledge;
- orchestrator/runtime;
- Agent API.

Adicionar/adaptar:
- concierge_summit profile;
- agenda tools;
- reservations;
- attendance;
- feedback;
- materials;
- personal itinerary;
- day-1 dossier / day-2 planning;
- opportunity detection.

Acceptance:
- same person from Sales can appear in Concierge without duplicate identity;
- Concierge can recommend based on known interests/objectives;
- feedback/attendance updates shared intelligence where appropriate.

## Fase 7 — Service + Researcher

### Service
- support cases;
- goals;
- health snapshots;
- milestones;
- satisfaction;
- handoffs.

### Researcher
- broad knowledge scope;
- deep retrieval;
- source/citation requirements;
- structured return to calling agent.

## Fase 8 — Institute / Dash / Events

Implement product-specific depth mantendo Agent API estável.

Profiles:
- sales_institute
- sales_dash
- sales_events

Playbook inheritance conforme apropriado.

## Fase 9 — Evals & optimization

- golden conversations;
- accuracy;
- relevance;
- naturalness;
- context use;
- conversion/resolution;
- hallucination checks;
- known-info re-questioning;
- human feedback;
- A/B de context profiles/playbooks;
- latency/cost monitoring.

## Operating discipline

Cada etapa deve terminar com:
1. acceptance test;
2. checkpoint commit;
3. atualização de `00_EXECUTION_CONTROL.md`;
4. atualização de docs afetados;
5. registro de ADR se houver mudança arquitetural.

## Regra de prioridade

Quando surgir demanda futura durante execução:
- perguntar se muda a arquitetura atual;
- se não mudar, registrar no backlog e continuar o passo ativo;
- se mudar, parar e avaliar impacto antes de codificar.

A urgência de Sales/Concierge não autoriza criar sistemas paralelos.