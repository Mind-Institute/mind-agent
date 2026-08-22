# MIND INTELLIGENCE — SECURITY & CHANGE PROTOCOL

## Objetivo

Impedir que velocidade de build, coding agents ou colaboradores criem risco operacional, vazamento de dados ou drift arquitetural.

## Ambientes

Target operacional:

```text
LOCAL / DEV
   ↓
STAGING / PREVIEW
   ↓
PRODUCTION
```

Produção não deve ser usada como ambiente normal de desenvolvimento ou teste.

## Banco

Regras:
- mudanças estruturais sempre versionadas;
- migrations revisáveis;
- nenhum `DROP`/destructive change sem checkpoint + impacto + rollback/recovery;
- evitar edição manual de schema pelo Dashboard como prática normal;
- novos schemas/tabelas precisam estar previstos pela arquitetura ou ADR;
- manter grants mínimos;
- revisar search_path de funções;
- preferir SECURITY INVOKER quando suficiente;
- SECURITY DEFINER exige justificativa e grants explícitos.

## RLS

Objetos expostos ao browser/app precisam de RLS/policies coerentes.

RLS habilitado sem policy pode bloquear legitimamente acesso, mas deve ser intencional e documentado.
RLS desligado em tabela sensível/exposta é risco.

Antes de go-live:
- inventariar exposed schemas;
- revisar tables/views/functions acessíveis a anon/authenticated;
- remover grants desnecessários;
- testar happy path e negative access tests.

## Public/API exposure

Target:
- `public` quase vazio para lógica de negócio;
- `api` custom schema para contratos seguros quando browser/app precisar;
- `agent_api` para contracts internos/agent-facing conforme desenho final;
- schemas internos não expostos diretamente sem necessidade.

## Secrets

Nunca colocar no frontend:
- service role;
- secret API keys;
- webhook secrets;
- tokens administrativos.

Edge Functions/server runtime guardam secrets.

Publishable/anon keys só são aceitáveis no client quando acompanhadas de RLS/permissions corretas.

## Webhooks

Cada webhook deve ter:
- autenticação/origin validation apropriada;
- idempotency/external event id;
- raw event preservation quando útil;
- status/error/retry tracking;
- logging sem PII desnecessário;
- safe failure behavior.

Não usar `verify_jwt=false` como equivalente a “público e seguro”. Se JWT estiver desabilitado, a função deve implementar autenticação própria apropriada ao webhook.

## External actions

Writes em HubSpot, Treble, email, calendário etc. devem:
- ser autorizados por action scope;
- possuir idempotency key quando possível;
- registrar audit/outbox;
- tolerar retry;
- não duplicar efeito.

## AI / data handling

- Reduzir PII enviada ao LLM quando não necessária.
- Não inferir atributos sensíveis.
- Não armazenar chain-of-thought.
- Guardar operational rationale curto, structured decision e evidence links.
- `store:false` quando política/runtime exigir e for suportado.
- Dados derivados devem carregar provenance/confidence.

## Current known security findings — 2026-08-22

Observados diretamente no projeto Supabase durante auditoria de leitura:
- múltiplas tabelas com RLS habilitado porém sem policies;
- funções SECURITY DEFINER acessíveis a `anon`/`authenticated` no schema público;
- funções com mutable search_path;
- extensões instaladas em `public`;
- leaked password protection desabilitado;
- Edge Functions públicas (`verify_jwt=false`) que dependem de mecanismos próprios de autenticação;
- diferença entre código versionado e funções publicadas.

Esses achados são **backlog obrigatório antes de go-live**, mas não devem ser corrigidos de forma oportunística no meio do checkpoint/migração sem plano.

## Change classes

### Classe A — conteúdo/config seguro
Ex.: copy versionada, seed não destrutivo.
Pode seguir fluxo normal com teste.

### Classe B — código/runtime
Ex.: Edge Function, tool, orchestrator.
Exige teste, observabilidade e rollback/redeploy possível.

### Classe C — schema/migration
Exige migration, validation query/test, dependency review e update de docs.

### Classe D — destrutiva/identity/source-of-truth
Ex.: mover pessoa canônica, drop legacy, alterar ids universais.
Exige checkpoint, migration plan, compatibility strategy, rollback/recovery e aprovação arquitetural explícita.

### Classe E — ação externa/produção
Ex.: envio em massa, CRM write, deploy prod, alteração de auth/permissions.
Exige autorização explícita, idempotency e audit.

## Protocol before implementation

1. Ler `README_FIRST.md`.
2. Ler `00_EXECUTION_CONTROL.md`.
3. Identificar classe da mudança.
4. Verificar source of truth.
5. Verificar dependências/FKs/consumidores.
6. Determinar se muda arquitetura.
7. Se muda: ADR + aprovação antes de código.
8. Implementar somente escopo pedido.
9. Testar acceptance criteria.
10. Atualizar documentação/status.

## Protocol for architecture changes

Criar ADR contendo:
- contexto/problema;
- decisão proposta;
- alternativas consideradas;
- impacto em dados/runtime/integrations;
- migration compatibility;
- risks;
- decisão/aprovação;
- data.

Não reabrir invariants fundamentais por conveniência local.

## Protocol for destructive migrations

Obrigatório:
- checkpoint recuperável;
- row counts/data validation se há dados;
- dependency map;
- compatibility view/RPC quando necessário;
- migration reversível ou recovery procedure;
- consumers migrated/tested;
- only then remove legacy.

## Coding agent permissions philosophy

Coding agents não devem ter acesso irrestrito à produção.
Preferir:
- local/dev branch;
- staging;
- explicit deploy step.

Se o coding agent tiver tecnicamente acesso, as regras de projeto ainda proíbem deploy/mutation sem tarefa explícita.

## Human onboarding

Novo colaborador deve conseguir responder antes de tocar código:
- qual é a entrega ativa?
- qual branch/ambiente posso alterar?
- posso mexer em produção? (não por padrão)
- onde está a canonical person?
- diferença entre product e product_run?
- onde preço é autoridade?
- como agents acessam dados?
- quando preciso de ADR?

Se não souber, ainda não deve fazer alteração estrutural.