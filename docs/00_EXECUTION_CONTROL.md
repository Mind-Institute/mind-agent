# MIND INTELLIGENCE — EXECUTION CONTROL

Este arquivo é a torre de controle operacional do projeto. Deve ser atualizado sempre que uma etapa relevante for concluída, bloqueada ou replanejada.

## Objetivo atual

Preparar a arquitetura e os contratos para entregar Sales Summit funcional end-to-end sem perder a arquitetura definitiva do Mind Intelligence.

## Próximo deadline operacional

Concierge Summit deve reutilizar o mesmo core compartilhado imediatamente após Sales Inbound.

## Estado da arquitetura

Status: FROZEN para os princípios e domínios principais.

Mudanças arquiteturais só podem ocorrer por decisão explícita documentada.

## CONCLUÍDO — FASE 0A: CHECKPOINT DO SISTEMA EXISTENTE

Checkpoint branch:
`checkpoint/pre-mind-intelligence-architecture`

Commit:
`372992ee22c32e1b0b6b300ad477b60ce41c3701`

Working tree: clean.

Capturado:
- 8 Edge Functions contabilizadas;
- 5 funções publicadas recuperadas da produção;
- 3 funções já estavam versionadas;
- 33 migration files no repo;
- ledger das 99 migrations aplicadas registrado;
- nada alterado no Supabase;
- nenhum merge em main;
- nenhum deploy.

### Gaps de recuperação conhecidos

1. `database-schema.sql` não foi gerado por bloqueio de rede/CLI ao Postgres/Supabase.
2. 71 migrations aplicadas não possuem arquivo correspondente no repositório; os statements existem no ledger do banco.
3. Conteúdo/configuração curada fora de migrations precisa ser preservado/migrado explicitamente, incluindo `treble.prompts`, `treble.config`, `summit.commercial_rules`, `summit.offers`, `engagement.origens`, `crm.mapa_produtos`.
4. Secrets de Edge Functions não são recuperáveis pelo checkpoint; apenas nomes estão conhecidos.
5. Bucket `mind-assets` não foi incluído no checkpoint.

Esses gaps são **restrições do migration plan**. Nenhuma estrutura correspondente deve ser destruída até existir recovery/compatibility/validation suficiente.

## ETAPA ATUAL — FASE 0B: CONSTITUIÇÃO, BEHAVIOR SPECS, EVALS E MEMÓRIA PERMANENTE

Objetivo: fazer o repositório carregar a visão estratégica, as regras de arquitetura e a definição de excelência do agente antes da primeira migration target.

### Já criado/atualizado
- `README_FIRST.md`
- `CLAUDE.md`
- `AGENTS.md`
- `docs/00_ARCHITECTURE.md`
- `docs/01_PROJECT_MEMORY.md`
- `docs/02_TARGET_DATA_MODEL.md`
- `docs/03_AGENT_RUNTIME_CONTEXT_MEMORY.md`
- `docs/04_PRODUCT_AND_COMMERCIAL_MODEL.md`
- `docs/05_IMPLEMENTATION_ROADMAP.md`
- `docs/06_SECURITY_AND_CHANGE_PROTOCOL.md`
- `docs/07_CURRENT_STATE_2026-08-22.md`
- `docs/08_AGENT_CONTRACTS.md`
- `docs/09_SOURCE_OF_TRUTH_DRAFT.md`
- `docs/10_GLOSSARY.md`
- `docs/11_SALES_AGENT_BEHAVIOR_SPEC.md`
- `docs/12_KNOWLEDGE_INGESTION_AND_RETRIEVAL.md`
- `docs/13_EVALS_AND_OBSERVABILITY.md`
- `docs/14_OUTBOUND_WORKFLOW.md`
- `docs/architecture-blueprint.html`

### Ainda precisa ser fechado antes de migration
- reconciliar documentação target com checkpoint e estado real;
- finalizar Source of Truth;
- criar Current → Target Map definitivo;
- criar Migration Plan físico;
- registrar ADRs iniciais dos invariants centrais;
- definir baseline executável de contracts/evals/tests para Vibe Code;
- decidir recovery/capture suficiente para os 71 migrations sem arquivo e configs fora de migrations.

## Definition of Done — Fase 0B

- colaborador novo entende visão, ordem e proibições sem depender de conversa histórica;
- Sales Behavior Spec define o que é um vendedor excelente antes de prompt/playbook;
- evals críticos existem antes do primeiro Sales runtime target;
- knowledge ingestion/retrieval distingue authoritative structured truth de semantic retrieval;
- identity model inclui contact points;
- privacy/contactability/suppression está arquitetado antes de outbound;
- observability inclui model/prompt/playbook/context versions + retrieval trace;
- coding agents sabem quais documentos ler por tipo de tarefa;
- nenhum documento target contradiz conscientemente o estado/checkpoint sem marcação explícita de migration.

## PRÓXIMA ETAPA — FASE 0C: CURRENT → TARGET + MIGRATION PLAN

Classificar cada estrutura atual como:
- KEEP
- REUSE + MOVE
- REBUILD
- DELETE
- DEFER

Para cada mudança relevante documentar:
- current object;
- target object;
- data/config a preservar;
- consumers/FKs;
- compatibility layer;
- validation/acceptance;
- rollback/recovery;
- quando legacy pode ser removido.

## Depois

### FASE 0D — DEV / STAGING / PROD + GUARDRAILS EXECUTÁVEIS
- permissions separadas;
- migrations controladas;
- secrets separados;
- RLS/security baseline;
- tests/contracts/eval fixtures.

### FASE 1 — IDENTITY + CATALOG
- people.people
- people.contact_points
- organizations/affiliations
- privacy/contactability foundation
- catalog products/product_runs
- integrations.external_refs

### FASE 2 — SUMMIT + COMMERCIAL + KNOWLEDGE MÍNIMO
- Summit 2026
- pessoas/palestrantes
- programação
- offers/preços/lotes/conditions/inclusions
- product content
- concepts/claims/sources mínimos
- ingestion/retrieval pattern

### FASE 3 — ENGAGEMENT + INTELLIGENCE + CRM CORE
- conversations/messages/entry_contexts/interactions
- facts/insights/intents/summaries/product_fit
- CRM relationship layer

### FASE 4 — SALES SUMMIT INBOUND E2E
- behavior spec → playbook
- decisioning
- agents/agent_api
- sales_summit profile
- Base Context / Context Planner
- tools essenciais
- Treble E2E
- context/retrieval trace
- golden evals/regressions

### FASE 5 — CONCIERGE SUMMIT
- mesmo identity/engagement/intelligence/runtime
- agenda/reservations/attendance/feedback/materials

### FASE 6 — SALES OUTBOUND
- trigger/eligibility
- contactability/consent/suppression
- cadence/state
- send/outbox/idempotency
- reply → normal Sales runtime

### FASE 7 — SERVICE / CS / SUPPORT + RESEARCHER

### FASE 8 — INSTITUTE / DASH / EVENTS

### FASE 9 — ADVANCED OPTIMIZATION
Evals já existem antes; aqui entram A/B, model/context/retrieval optimization, cost/latency e expansão contínua.

## Não fazer agora

- não iniciar migrations target antes de Current → Target + Migration Plan;
- não apagar estruturas atuais;
- não perder os 71 migration statements/configurações fora de migration;
- não refatorar Sales/Concierge de produção durante documentação;
- não alterar produção manualmente;
- não construir outbound/CS/Institute/Dash agora;
- não criar novas abstrações fora da arquitetura target;
- não tratar “evals” como trabalho futuro opcional;
- não transformar embeddings/RAG em fonte universal de verdade.

## Decisões congeladas

- `people.people` = pessoa canônica.
- `people.contact_points` = meios/identificadores humanos de contato; não external system ids.
- `crm.contacts` = relação comercial, não identidade canônica.
- `catalog.products` = produto; `catalog.product_runs` = edição/turma/entrega concreta.
- `summit.editions` = facet 1:1 de product_run.
- Sales e Concierge usam core compartilhado de identity, engagement, intelligence e runtime.
- Uma pessoa pode ter múltiplas conversations por canal; continuidade vem da memória/identity compartilhada.
- Intelligence != Playbook != Decisioning != Agent.
- `intelligence.facts` não duplica silenciosamente domínios canônicos.
- Agent API esconde topologia do banco.
- Base Context mínimo + retrieval just-in-time.
- Structured authoritative truth antes de generic semantic/vector retrieval.
- Dados derivados por IA guardam provenance/confidence.
- Outbound depende de contactability/suppression determinísticos.
- Agent runs devem ser reproduzíveis por versões + context/retrieval trace, sem chain-of-thought.
- Evals começam antes do primeiro agent target.
- Product schemas podem diferir internamente; contracts para agents permanecem consistentes.

## Achados relevantes do sistema atual

- Sales atual já possui guardrails comerciais úteis e deve servir de referência para migração.
- Concierge atual possui identidade/sessão/personalização mais madura e deve servir de referência para o core compartilhado.
- Sales e Concierge possuem runtimes paralelos e isso deve ser eliminado na arquitetura target.
- `crm.pessoas` concentra muitas foreign keys e sua migração exige coordenação.
- `catalogo.produtos` mistura produto e edição/turma.
- ofertas/preços hoje estão em Summit, target é `commercial` compartilhado.
- há riscos de segurança/RLS/funções privilegiadas antes de go-live.
- repo/publicado/DB history ainda apresentam drift que precisa ser reconciliado.

## Regra de atualização deste arquivo

Ao concluir cada etapa:
1. mover a etapa para CONCLUÍDO;
2. registrar o que mudou;
3. registrar gaps/bloqueios;
4. atualizar PRÓXIMA ETAPA;
5. atualizar NÃO FAZER AGORA;
6. nunca apagar histórico importante — use ADRs quando necessário.