# MIND INTELLIGENCE — EXECUTION CONTROL

Este arquivo é a torre de controle operacional do projeto. Deve ser atualizado sempre que uma etapa relevante for concluída, bloqueada ou replanejada.

## Objetivo atual

Entregar Sales Summit funcional end-to-end, preservando a arquitetura definitiva do Mind Intelligence.

## Próximo deadline

Concierge Summit deve reutilizar o mesmo core compartilhado imediatamente após Sales.

## Estado da arquitetura

Status: FROZEN para os princípios e domínios principais.

Mudanças arquiteturais só podem ocorrer por decisão explícita documentada.

## Etapa atual

FASE 0A — CHECKPOINT DO SISTEMA EXISTENTE

O Claude Code está criando um checkpoint recuperável do estado atual antes de qualquer migração.

## Fazendo agora

- preservar código local atual;
- preservar Edge Functions publicadas;
- preservar schema atual do banco;
- garantir branch/commit recuperável;
- NÃO alterar Supabase funcionalmente.

## Definition of Done — Fase 0A

- branch de checkpoint criada;
- working tree conhecido;
- todas as Edge Functions publicadas preservadas em código;
- migrations atuais preservadas;
- snapshot estrutural do banco salvo, sem dados pessoais;
- nenhuma mudança funcional aplicada em produção.

## Próxima etapa

FASE 0B — CONSTITUIÇÃO E MEMÓRIA PERMANENTE DO PROJETO

Entregáveis:
- README_FIRST.md
- CLAUDE.md
- AGENTS.md
- arquitetura oficial
- source-of-truth
- agent contracts
- security/access rules
- change protocol
- data dictionary inicial
- current-to-target map
- migration plan

## Depois

FASE 0C — PLANO DE MIGRAÇÃO FÍSICA

Mapear o estado real do Supabase para a arquitetura target e classificar cada estrutura como:
- KEEP
- REUSE + MOVE
- REBUILD
- DELETE
- DEFER

FASE 0D — DEV / STAGING / PROD E GUARDRAILS

FASE 1 — IDENTIDADE + CATÁLOGO
- people
- catalog
- integrations.external_refs

FASE 2 — SUMMIT + COMMERCIAL
- Summit 2026
- pessoas/palestrantes
- programação
- MIND/VIP/PRIME/Corporate
- preços/lotes/condições/inclusions

FASE 3 — ENGAGEMENT + INTELLIGENCE + CRM CORE
- conversations/messages/entry_contexts
- facts/insights/intents/summaries/product_fit
- CRM relationship layer

FASE 4 — SALES SUMMIT RUNTIME
- playbooks
- decisioning
- agents
- agent_api
- sales_summit profile
- Base Context
- Context Planner mínimo
- tools essenciais
- Treble end-to-end

FASE 5 — MEMORY LOOP + AUTOMAÇÃO COMERCIAL
- extract-turn-intelligence
- refresh-summary
- evaluate-opportunity
- HubSpot sync
- tasks/follow-ups

FASE 6 — CONCIERGE SUMMIT
- concierge_summit profile
- agenda/reservations/attendance/feedback
- mesma identity, engagement e intelligence

FASE 7 — SERVICE + RESEARCHER

FASE 8 — INSTITUTE / DASH / EVENTS

FASE 9 — EVALS / OPTIMIZATION

## Não fazer agora

- não migrar tabelas antes do checkpoint e da documentação;
- não apagar estruturas atuais;
- não refatorar Sales enquanto o estado atual não estiver preservado;
- não refatorar Concierge enquanto o estado atual não estiver preservado;
- não alterar produção manualmente;
- não criar novas abstrações fora da arquitetura target;
- não iniciar Customer Success/Researcher/Institute/Dash antes da vertical Sales estar funcional.

## Decisões congeladas

- `people.people` será a pessoa canônica.
- `crm.contacts` é relação comercial e não identidade canônica.
- `catalog.products` representa produto; `catalog.product_runs` representa edição/turma/entrega concreta.
- `summit.editions` é faceta 1:1 de um `product_run_id`, não uma segunda identidade.
- Sales e Concierge usarão um core compartilhado de identity, engagement, intelligence e runtime.
- Intelligence != Playbook != Decisioning != Agent.
- Agent API esconde a topologia do banco.
- Base Context deve ser mínimo e retrieval adicional deve ser just-in-time.
- Dados derivados por IA guardam source + confidence + provenance.
- Product schemas podem diferir internamente; contratos consumidos pelos agentes devem permanecer consistentes.

## Achados relevantes do sistema atual

- Sales atual já possui guardrails comerciais úteis e deve servir de referência para a migração.
- Concierge atual possui identidade/sessão/personalização mais madura e deve servir de referência para o core compartilhado.
- Hoje Sales e Concierge possuem runtimes paralelos e isso deve ser eliminado na arquitetura target.
- `crm.pessoas` atualmente concentra muitas foreign keys e sua migração exige coordenação, não rename improvisado.
- `catalogo.produtos` mistura produto e edição/turma; deve ser normalizado em product + product_run.
- ofertas/preços hoje estão em Summit, mas o target é `commercial` compartilhado.
- há riscos de segurança/RLS e funções privilegiadas a corrigir antes de go-live.

## Regra de atualização deste arquivo

Ao concluir cada etapa:
1. mover a etapa para CONCLUÍDO;
2. registrar o que mudou;
3. registrar bloqueios;
4. atualizar PRÓXIMA ETAPA;
5. atualizar NÃO FAZER AGORA;
6. nunca apagar o histórico de decisões importantes — use ADRs quando necessário.
