# MIND INTELLIGENCE — EXECUTION CONTROL

Este arquivo é a torre de controle operacional do projeto. Deve ser atualizado sempre que uma etapa relevante for concluída, bloqueada ou replanejada.

## Objetivo atual

Entregar Sales Summit funcional end-to-end sem perder a arquitetura definitiva do Mind Intelligence.

## Próximo deadline operacional

Concierge Summit deve reutilizar o mesmo core compartilhado imediatamente após Sales Inbound.

## Estado da arquitetura

Status: FROZEN para os princípios e domínios principais.

A reconciliação com o sistema real gerou apenas ajustes explícitos registrados em `docs/16_TARGET_ADJUSTMENTS_FROM_RECONCILIATION.md`.

Mudanças arquiteturais futuras só podem ocorrer por decisão explícita documentada.

Regra operacional atual de migração/reuso:
- `docs/19_LEGACY_REUSE_AND_MIGRATION_POLICY.md`
- o sistema atual NÃO é descartável;
- infraestrutura, integrações, contratos e dados operacionais podem ser importantes para continuidade;
- conteúdo/config/regra existente NÃO é automaticamente confiável ou aprovado;
- revisão do sistema atual acontece just-in-time por objeto target;
- cada objeto decide `REUSE / TRANSFORM / REBUILD / DO NOT MIGRATE`;
- nada é migrado apenas porque existe;
- `DO NOT MIGRATE` não autoriza apagar estrutura viva antes de consumer/cutover verification.

---

## CONCLUÍDO — FASE 0A: CHECKPOINT DO SISTEMA EXISTENTE

Checkpoint branch:
`checkpoint/pre-mind-intelligence-architecture`

Commit:
`372992ee22c32e1b0b6b300ad477b60ce41c3701`

Capturado originalmente:
- 8 Edge Functions contabilizadas;
- 5 funções publicadas recuperadas da produção;
- 3 funções já estavam versionadas;
- ledger das 99 migrations aplicadas registrado;
- nada alterado no Supabase;
- nenhum deploy.

### Recovery complementar — concluído

- as 71 migrations aplicadas que não tinham arquivo correspondente foram recuperadas e arquivadas no Git;
- as 5 Edge Functions production-only estão arquivadas em `archive/pre-architecture/`;
- PR #7 foi mergeado;
- PR #6 foi fechado sem merge como superseded.

### Gaps remanescentes relevantes

1. ainda falta structural schema baseline ou equivalente reproduzível;
2. secrets devem ser conhecidos por nome/dependência, nunca por valor no Git;
3. `mind-assets` só é blocker quando um target/cutover depender de asset cuja continuidade não esteja protegida;
4. consumers/security serão mapeados just-in-time conforme os objetos target forem tocados.

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

Ajustes do target congelados:
- `docs/16_TARGET_ADJUSTMENTS_FROM_RECONCILIATION.md`

Diagnóstico:
- arquitetura target continua válida;
- migração é cirúrgica e não destrutiva;
- current system é consultado por objeto no momento da implementação;
- live continuity permanece protegida até cutover validado.

---

## CONCLUÍDO — FASE 0D: MIGRATION PLAN CORRIGIDO PARA EXECUÇÃO JUST-IN-TIME

Documentos:
- `docs/17_MIGRATION_PLAN.md`
- `docs/19_LEGACY_REUSE_AND_MIGRATION_POLICY.md`

Decisões autoritativas adicionadas em 2026-08-22:
- dados de interação atuais do Concierge são TESTE e não são target backfill requirement;
- prompts/playbooks/templates/configs/regras/conteúdo criados durante prototipagem não são business truth por padrão;
- conteúdo comercial atual exige validação explícita antes de virar Playbook, Decisioning, Intelligence, Knowledge ou Source of Truth;
- não existe bulk migration obrigatório de conteúdo/config não validado;
- revisão é just-in-time por target object;
- dados e contratos operacionais podem ser reutilizados quando validados e necessários para continuidade;
- sistema atual não deve ser apagado casualmente nem tratado como descartável.

---

## ETAPA ATUAL — WAVE 0 REDUZIDA: RECOVERY + ENVIRONMENT SAFETY

### Objetivo

Fechar apenas o mínimo necessário para iniciar a primeira migration target de forma segura, reversível e testável.

### Já concluído

- 71 migrations recuperadas;
- production-only Edge Functions recuperadas;
- current→target map concluído;
- migration plan corrigido;
- política just-in-time registrada.

### Falta antes da primeira migration target

1. obter structural schema baseline ou snapshot equivalente reproduzível, preferencialmente automatizado;
2. identificar consumers/contracts que podem ser afetados pela PRIMEIRA target migration;
3. documentar nomes/dependências de secrets necessários, sem valores;
4. estabelecer dev/staging seguro para testar a primeira migration;
5. identificar RLS / SECURITY DEFINER / search_path / public-execute risks apenas nos objetos que a primeira target migration tocar.

### Explicitamente NÃO é blocker

- exportar em massa prompts/configs/templates atuais;
- revisar todo conteúdo de negócio antes de começar implementação;
- backfill de dados de interação do Concierge;
- inventário completo de todo asset/consumer do sistema;
- auditoria de segurança do banco inteiro antes de Wave 1.

### Exit criteria

- produção atual reproduzível/recuperável o suficiente para comparação e rollback;
- dev/staging seguro disponível;
- dependências que podem quebrar com a primeira target change são conhecidas;
- secret dependencies necessárias são conhecidas sem copiar valores;
- security risks relevantes aos primeiros objetos são conhecidos;
- nenhum dado/contrato operacional necessário ao primeiro cutover depende de uma cópia desconhecida.

---

## DEPOIS — ORDEM CONGELADA

### FASE 1 — IDENTITY + CATALOG
- people.people
- people.contact_points
- people.identity_merges
- organizations/affiliations
- privacy/contactability foundation
- catalog products/product_runs/product_components
- integrations.external_refs/value_mappings
- review current-system correspondente just-in-time por objeto.

### FASE 2 — SUMMIT + COMMERCIAL + KNOWLEDGE MÍNIMO
- Summit 2026 / edition facet
- pessoas/palestrantes
- programação/locations/navigation necessários
- offers/preços/lotes/conditions/inclusions/discount codes
- product content
- concepts/claims/sources mínimos
- ingestion/retrieval pattern
- conteúdo comercial só entra quando validado.

### FASE 3 — ENGAGEMENT + INTELLIGENCE + CRM CORE
- conversations/messages/entry_points/entry_contexts/interactions
- facts/insights/intents/summaries/product_fit
- CRM relationship layer
- Concierge test data não é backfill.

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

---

## Não fazer agora

- não fazer bulk export/migration de conteúdo/config não validado;
- não tratar conteúdo existente como business truth por default;
- não apagar current-system objects antes de consumer/cutover verification;
- não alterar Supabase de produção enquanto Wave 0 reduzida não tiver saído;
- não habilitar RLS em massa;
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
