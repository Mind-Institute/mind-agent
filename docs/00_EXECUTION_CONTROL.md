# MIND INTELLIGENCE — EXECUTION CONTROL

Este arquivo é a torre de controle operacional do projeto. Deve ser atualizado sempre que uma etapa relevante for concluída, bloqueada ou replanejada.

## Objetivo atual

Preparar a arquitetura, os contratos e o plano de migração para entregar Sales Summit funcional end-to-end sem perder a arquitetura definitiva do Mind Intelligence.

## Próximo deadline operacional

Concierge Summit deve reutilizar o mesmo core compartilhado imediatamente após Sales Inbound.

## Estado da arquitetura

Status: FROZEN para os princípios e domínios principais.

A reconciliação com o sistema real gerou apenas ajustes explícitos registrados em `docs/16_TARGET_ADJUSTMENTS_FROM_RECONCILIATION.md`.

Mudanças arquiteturais futuras só podem ocorrer por decisão explícita documentada.

---

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
- nenhum deploy.

### Gaps de recuperação conhecidos

1. `database-schema.sql` não foi gerado por bloqueio de rede/CLI ao Postgres/Supabase.
2. 71 migrations aplicadas não possuem arquivo correspondente no repositório; os statements existem no ledger do banco.
3. Conteúdo/configuração curada fora de migrations precisa ser preservado/migrado explicitamente, incluindo `treble.prompts`, `treble.config`, `summit.commercial_rules`, `summit.offers`, `engagement.origens`, `crm.mapa_produtos` e configurações úteis do Concierge.
4. Secrets de Edge Functions não são recuperáveis pelo checkpoint; apenas nomes estão conhecidos.
5. Bucket `mind-assets` não foi incluído no checkpoint.

Esses gaps são restrições do Migration Plan. Nenhuma estrutura correspondente deve ser destruída até existir recovery/compatibility/validation suficiente.

---

## CONCLUÍDO — FASE 0B: CONSTITUIÇÃO, BEHAVIOR SPECS, EVALS E MEMÓRIA PERMANENTE

A constituição Mind Intelligence v1 foi promovida para `main`.

Documentos principais:
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

### Definition of Done atingida

- colaborador novo consegue reconstruir a visão sem depender da conversa histórica;
- Sales Behavior Spec define excelência antes de prompt/playbook;
- evals são parte do desenvolvimento desde antes do primeiro runtime target;
- knowledge ingestion/retrieval distingue authoritative structured truth de semantic retrieval;
- identity model separa person/contact point/external ref/CRM contact;
- privacy/contactability/suppression está arquitetado antes de outbound;
- observability inclui model/prompt/playbook/context versions + retrieval trace;
- coding agents sabem quais documentos ler e quando devem parar diante de conflito arquitetural.

---

## CONCLUÍDO — FASE 0C: CURRENT → TARGET RECONCILIATION

Objetivo: confrontar arquitetura target com o Supabase/GitHub reais antes de escrever qualquer migration target.

Resultado principal:
- `docs/15_CURRENT_TO_TARGET_MAP.md`

O mapa classifica estruturas atuais como:
- KEEP
- MOVE
- EVOLVE
- MERGE
- SPLIT
- REBUILD
- RETIRE
- TARGET ADJUSTMENT

Também registra prioridades P0–P3, comportamento a preservar, riscos de recovery/security, APIs/Edge Functions e ondas lógicas de migração.

### Ajustes do target descobertos e congelados

Registrados em:
`docs/16_TARGET_ADJUSTMENTS_FROM_RECONCILIATION.md`

Incluem:
- `people.identity_merges`;
- `catalog.product_components`;
- `commercial.discount_codes`;
- `engagement.entry_points`;
- `privacy.data_requests`;
- preservação de polls/exhibitors/navigation/event rules/networking no Summit quando aplicável;
- manutenção de um domínio de infraestrutura `platform` para model/provider/embedding routing e telemetria;
- `integrations.value_mappings`;
- recomendação de preservar o nome físico `summit.locations` salvo conflito semântico real.

### Diagnóstico final da reconciliação

A arquitetura target continua válida. A migração deve ser cirúrgica, não destrutiva:
- preservar IDs/dados/comportamentos quando útil;
- mudar ownership/topologia quando necessário;
- usar compatibility layers durante cutover;
- só retirar legado após consumer/data/config verification.

---

## ETAPA ATUAL — FASE 0D: MIGRATION PLAN + SOURCE OF TRUTH FINAL

### Objetivo

Converter o Current → Target Map em uma sequência executável de mudanças sem ainda alterar produção.

O documento principal será:
`docs/17_MIGRATION_PLAN.md`

Em paralelo, `docs/09_SOURCE_OF_TRUTH_DRAFT.md` deve ser fechado como versão final quando as autoridades operacionais restantes forem confirmadas.

### O Migration Plan deve especificar por onda

Para cada mudança:
- objeto atual;
- objeto target;
- dependências/FKs/consumers;
- IDs e dados a preservar;
- config a exportar/versionar;
- nova schema/table/function necessária;
- backfill;
- dual-read/dual-write ou wrapper, se necessário;
- teste antes/depois;
- security/RLS;
- rollback/recovery;
- critério de cutover;
- critério para remover legacy;
- responsável/coding-agent task boundary.

### P0 que o plano deve resolver antes de qualquer operação destrutiva

1. estratégia de baseline/recovery para as 71 migrations sem arquivo;
2. captura/versionamento de configuração curada fora de migration;
3. inventário/recovery do `mind-assets` quando necessário;
4. mapa de consumidores das Edge Functions/RPCs legadas;
5. estratégia para as 12 tabelas atualmente com RLS desabilitado;
6. revisão de funções privilegiadas/security-definer/search_path relevantes;
7. ambiente seguro de desenvolvimento/staging para testar migrations antes de produção.

## Definition of Done — Fase 0D

- existe uma sequência física de migração sem saltos arquiteturais;
- cada wave tem entrada, saída, acceptance test e rollback;
- nenhuma estrutura atual é removida sem consumer check;
- Sales e Concierge permanecem recuperáveis durante a transição;
- os P0 de recovery/security têm tratamento explícito;
- Source of Truth deixa de ser DRAFT ou mantém apenas exceções explicitamente bloqueadas;
- a primeira tarefa de implementation para o coding agent é pequena, reversível e testável.

---

## PRÓXIMA ETAPA — FASE 0E: DEV / STAGING / PROD + GUARDRAILS EXECUTÁVEIS

Antes de alterar produção:
- environment separation;
- permissions separadas;
- migrations controladas;
- secrets separados;
- RLS/security baseline;
- DB tests/contracts/eval fixtures;
- deploy protocol.

---

## Depois

### FASE 1 — IDENTITY + CATALOG
- people.people
- people.contact_points
- people.identity_merges
- organizations/affiliations
- privacy/contactability foundation
- catalog products/product_runs/product_components
- integrations.external_refs/value_mappings

### FASE 2 — SUMMIT + COMMERCIAL + KNOWLEDGE MÍNIMO
- Summit 2026 / edition facet
- pessoas/palestrantes
- programação/locations/navigation necessários
- offers/preços/lotes/conditions/inclusions/discount codes
- product content
- concepts/claims/sources mínimos
- ingestion/retrieval pattern

### FASE 3 — ENGAGEMENT + INTELLIGENCE + CRM CORE
- conversations/messages/entry_points/entry_contexts/interactions
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
- agenda/reservations/attendance/feedback/materials/navigation

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

---

## Não fazer agora

- não criar migration target ainda;
- não alterar Supabase de produção;
- não habilitar RLS em massa sem policies/consumer analysis;
- não apagar estruturas atuais;
- não perder os 71 migration statements/configurações fora de migration;
- não refatorar Sales/Concierge enquanto o Migration Plan não definir compatibility/cutover;
- não construir outbound/CS/Institute/Dash agora;
- não criar abstrações fora da arquitetura target;
- não tratar evals como trabalho futuro opcional;
- não transformar embeddings/RAG em fonte universal de verdade.

---

## Decisões congeladas

- `people.people` = pessoa canônica.
- `people.contact_points` = meios/identificadores humanos de contato; não external system ids.
- `people.identity_merges` preserva histórico de fusão de identidade.
- `crm.contacts` = relação comercial, não identidade canônica.
- `catalog.products` = produto; `catalog.product_runs` = edição/turma/entrega concreta.
- `catalog.product_components` representa composição many-to-many quando necessário.
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

---

## Regra de atualização deste arquivo

Ao concluir cada etapa:
1. mover a etapa para CONCLUÍDO;
2. registrar o que mudou;
3. registrar gaps/bloqueios;
4. atualizar ETAPA ATUAL e PRÓXIMA ETAPA;
5. atualizar NÃO FAZER AGORA;
6. nunca apagar histórico importante — use ADRs quando necessário.