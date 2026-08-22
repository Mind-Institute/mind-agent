# MIND INTELLIGENCE — IMPLEMENTATION ROADMAP

Este documento preserva a ordem macro de construção. `docs/00_EXECUTION_CONTROL.md` define qual passo está ativo AGORA.

## Fase 0A — Checkpoint do sistema existente

Objetivo: tornar o protótipo atual recuperável antes de qualquer mudança estrutural.

Definition of Done:
- branch de checkpoint;
- working tree conhecido;
- migrations preservadas na medida disponível;
- Edge Functions publicadas preservadas;
- snapshot estrutural do banco quando tecnicamente possível;
- gaps de recuperação explicitamente documentados;
- nenhum deploy/refactor funcional.

Estado conhecido após checkpoint de 2026-08-22:
- branch `checkpoint/pre-mind-intelligence-architecture` criada e limpa;
- 8 Edge Functions contabilizadas; 5 recuperadas da produção e 3 já versionadas;
- 33 migration files no repo;
- 99 migrations aplicadas no banco;
- 71 migrations aplicadas sem arquivo correspondente no repo;
- schema dump ainda não gerado por bloqueio de rede/CLI;
- configuração curada fora de migrations identificada como risco;
- bucket `mind-assets` e secrets não capturados.

Esses gaps devem entrar no plano de recuperação/migração antes de qualquer destruição de legado.

## Fase 0B — Constituição, comportamento e memória permanente

Entregáveis normativos:
- `README_FIRST.md`
- `CLAUDE.md`
- `AGENTS.md`
- architecture
- project memory
- target data model
- source of truth
- security/change protocol
- agent contracts
- current state
- migration plan
- ADRs iniciais
- Sales Behavior Spec
- knowledge ingestion/retrieval spec
- evals/observability spec
- outbound workflow architecture

Definition of Done:
- colaborador novo entende visão, regras e estado atual sem depender de conversa histórica;
- coding agent recebe instruções claras para não redesenhar arquitetura;
- conceitos e fronteiras de domínio estão documentados;
- comportamento esperado do primeiro Sales Agent está especificado antes do prompt/playbook;
- golden eval families e hard failures existem antes da primeira implementação de Sales;
- knowledge ingestion/retrieval distingue structured truth de semantic retrieval;
- requisitos fundacionais de outbound (contact points, privacy/contactability, suppression, observability) estão arquitetados sem implementar o workflow ainda.

## Fase 0C — Current → Target + plano de migração física

Comparar estado real com target.

Classificar cada estrutura:
- KEEP
- REUSE + MOVE
- REBUILD
- DELETE
- DEFER

O plano deve incluir:
- source object;
- target object;
- data movement/transformation;
- consumers/FKs;
- compatibility layer;
- validation query/acceptance;
- rollback/recovery;
- momento seguro de remover legacy.

Priorizar compatibility layer quando consumidores existentes ainda dependem de estruturas legadas.

Antes de qualquer Classe D/destrutiva, resolver ou aceitar explicitamente os gaps do checkpoint.

## Fase 0D — Ambientes, segurança e checks executáveis

- dev/local;
- staging/preview;
- prod;
- permissions separadas;
- migrations controladas;
- secrets separados;
- RLS/security baseline;
- contratos versionados;
- `supabase/tests/` mínimos;
- golden eval fixtures mínimas;
- PR/checklist de arquitetura quando viável.

Objetivo: documentação virar também restrição executável.

## Fase 1 — Identity + Catalog core

Schemas/responsabilidades:
- people
- privacy/contactability mínimo
- catalog
- integrations.external_refs

Tasks:
- canonical person model;
- `people.contact_points`;
- organizations/affiliations;
- canonical product families/products;
- product_runs;
- Summit 2026 como run;
- external id mapping;
- consent/contactability/suppression foundation suficiente para não exigir retrofit no outbound.

Acceptance:
- `get_person_context` resolve pessoa de forma estável;
- email/telefone/contact point não são confundidos com HubSpot/Treble external ids;
- Mind Summit e Summit 2026 não são duplicados;
- Treble/App conseguem apontar para mesma pessoa;
- contactability pode representar “pode/não pode contactar” sem LLM decidir isso.

Checkpoint commit.

## Fase 2 — Summit + Commercial + Knowledge mínimo

Schemas:
- summit
- commercial
- people product roles
- knowledge mínimo
- catalog product_content

Tasks:
- migrar/reaproveitar agenda, sessões, espaços e speakers;
- normalizar speakers para people;
- offers MIND/VIP/PRIME/Corporate;
- pricing periods/lotes;
- prices;
- discount rules;
- inclusions;
- checkout/attribution compatibility;
- source registration/versioning pattern;
- conceitos/product/session links mínimos;
- small curated scientific/product knowledge set;
- retrieval hierarchy estruturada antes de vector search genérico.

Acceptance:
`get_product_context(Summit 2026)` retorna produto, run, positioning relevante, people, commercial e concepts sem o agent conhecer tabelas.

Testes adicionais:
- preço vem de commercial authoritative source;
- agenda vem de Summit authoritative source;
- scientific question pode recuperar claim/source relevante;
- stale semantic text não sobrepõe structured truth.

Checkpoint commit.

## Fase 3 — Engagement + Intelligence + CRM relationship

Schemas:
- engagement
- intelligence
- crm core

Tasks:
- conversation model compartilhado;
- múltiplas conversations por pessoa/canal quando necessário;
- messages;
- entry_contexts;
- interactions;
- facts;
- insights;
- intents;
- summaries;
- product_fit;
- CRM contact/company/deal linkage.

Regra:
`intelligence.facts` não duplica email, purchase, price ou outras entidades que já têm representação canônica adequada.

Acceptance:
- pessoa inicia conversa pelo Treble;
- identidade é ligada;
- mensagens persistem;
- pessoa retorna em nova conversation e contexto anterior é recuperado via shared identity/intelligence;
- known information não precisa ser re-perguntada;
- insight inferido permanece distinguível de fato verificado.

Checkpoint commit.

## Fase 4 — Sales Summit Inbound E2E

Schemas/capabilities:
- playbooks
- decisioning
- agents
- agent_api
- evals baseline

Tasks:
- implementar contra `docs/11_SALES_AGENT_BEHAVIOR_SPEC.md`;
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
- persist run/decision/action;
- context manifest/retrieval trace;
- golden regression suite crítica.

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

Additional acceptance:
- hard-failure evals pass;
- price/agenda facts use authoritative tools;
- run can be reproduced by model/prompt/playbook/context versions + retrieval trace;
- no unauthorized external effect.

Checkpoint commit.

## Fase 5 — Concierge Summit sobre o mesmo core

Reutilizar:
- people/contact points;
- catalog;
- Summit;
- commercial/access rights;
- engagement;
- intelligence;
- knowledge;
- orchestrator/runtime;
- Agent API;
- observability/evals.

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
- app conversation may be separate from WhatsApp conversation while sharing relationship memory;
- Concierge can recommend based on known interests/objectives;
- feedback/attendance updates shared intelligence where appropriate;
- behavior remains non-invasive;
- Concierge golden cases pass.

## Fase 6 — Sales Outbound workflow

Reutilizar Sales runtime, mas adicionar:
- trigger registry;
- eligibility;
- why-now reason;
- privacy/contactability/suppression check;
- cadence/state machine;
- send/outbox/idempotency;
- owner/human coordination;
- reply transition into normal Sales runtime.

Referência normativa: `docs/14_OUTBOUND_WORKFLOW.md`.

Acceptance:
- opt-out/suppression blocks send deterministically;
- duplicate retry does not duplicate send;
- message uses current authoritative product/commercial context;
- reply joins normal relationship intelligence;
- owner/cadence rules are respected;
- outbound evals pass.

## Fase 7 — Service / Customer Success / Support + Researcher

### Service
- support cases;
- customer relationships;
- goals;
- health snapshots;
- milestones;
- satisfaction;
- handoffs;
- next-best actions/opportunity where appropriate.

### Researcher
- broad knowledge scope;
- deep retrieval;
- source/citation requirements;
- structured return to calling agent;
- no default authority for unrelated external writes.

Acceptance:
- Support/CS share identity/history with Sales/Concierge;
- Researcher is delegated only when required;
- research output preserves sources/caveats;
- service can hand off opportunity without duplicating CRM/people.

## Fase 8 — Institute / Dash / Events

Implement product-specific depth mantendo Agent API estável.

Profiles:
- sales_institute
- sales_dash
- sales_events

Playbook inheritance conforme apropriado.

Knowledge ingestion follows the same source/provenance/retrieval architecture.

## Fase 9 — Advanced optimization

Evals já existem desde Fase 0/4. Aqui entram otimizações mais sofisticadas:
- expand golden conversations from production failures;
- A/B context profiles;
- summary + recent vs fuller history;
- model/provider comparisons;
- reranker/retrieval variants;
- playbook versions;
- delegation thresholds;
- latency/cost optimization;
- conversion/resolution cohort analysis;
- human feedback loops;
- red-team/regression expansion.

Objetivo: melhorar com evidência, não começar tarde a medir qualidade.

## Continuous tracks — começam cedo e nunca “acabam”

### Evals
Acompanham behavior spec, prompts, models, playbooks, tools e context changes.

### Observability
Run/version/tool/context/retrieval trace desde o primeiro agent real.

### Memory quality
Evitar lixo, duplicação e over-inference.

### Knowledge quality
Freshness, authority, provenance, retrieval precision.

### Security/privacy
RLS, permissions, secrets, contactability, suppression, audit.

### Documentation
Atualizar execution control, current state, ADRs e contracts conforme sistema muda.

## Operating discipline

Cada etapa deve terminar com:
1. acceptance test;
2. regression evals pertinentes;
3. checkpoint commit;
4. atualização de `00_EXECUTION_CONTROL.md`;
5. atualização de docs afetados;
6. registro de ADR se houver mudança arquitetural.

## Regra de prioridade

Quando surgir demanda futura durante execução:
- perguntar se muda a arquitetura atual;
- se não mudar, registrar no backlog e continuar o passo ativo;
- se mudar, parar e avaliar impacto antes de codificar.

A urgência de Sales/Concierge não autoriza criar sistemas paralelos.