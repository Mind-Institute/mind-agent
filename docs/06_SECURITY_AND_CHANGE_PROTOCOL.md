# MIND INTELLIGENCE — SECURITY & CHANGE PROTOCOL

## Objetivo

Impedir que velocidade de build, coding agents ou colaboradores criem risco operacional, vazamento de dados, contato indevido ou drift arquitetural.

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
- SECURITY DEFINER exige justificativa e grants explícitos;
- não destruir legacy enquanto consumers/configuração/recovery não estiverem mapeados.

## Checkpoint/recovery constraints atuais

Antes de qualquer migration destrutiva, considerar os gaps do checkpoint de 2026-08-22:
- 71 migrations aplicadas sem arquivo correspondente no repo;
- schema dump estrutural ainda ausente por bloqueio de rede/CLI;
- configuração curada existente fora de migrations;
- secrets não recuperáveis pelo checkpoint;
- bucket `mind-assets` não capturado.

Esses itens não impedem toda evolução, mas impedem remoção irresponsável de estruturas que podem conter a única cópia recuperável de lógica/configuração.

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

## Privacy / contactability / outbound

Outbound e mensagens proativas exigem controles determinísticos antes do LLM:
- contact point válido/verificado quando aplicável;
- consent/legal basis conforme política aplicável;
- opt-out;
- channel suppression;
- global do-not-contact;
- communication preferences;
- cadence/recent-contact policy;
- active human owner/coordination policy quando aplicável.

O LLM pode sugerir uma mensagem, mas **não pode sobrescrever uma suppression/contactability negativa**.

Qualquer send workflow deve registrar:
- why-now/trigger;
- eligibility result;
- privacy/contactability decision;
- idempotency key;
- provider external id;
- delivery/result;
- follow-up state.

Ver `docs/14_OUTBOUND_WORKFLOW.md`.

## AI / data handling

- Reduzir PII enviada ao LLM quando não necessária.
- Não inferir atributos sensíveis.
- Não armazenar chain-of-thought.
- Guardar operational rationale curto, structured decision e evidence links.
- `store:false` quando política/runtime exigir e for suportado.
- Dados derivados devem carregar provenance/confidence.
- Context manifest/retrieval trace deve guardar referências e versões, não raciocínio privado.
- Não enviar dados irrelevantes ao modelo “por precaução”.

## Knowledge/data authority safety

- preço, disponibilidade, agenda, acesso e pagamento usam authoritative structured data quando disponível;
- embeddings/document chunks não substituem fonte operacional;
- ingestion não pode sobrescrever domínio mais autoritativo sem política explícita;
- stale content precisa ser detectável/invalidadável;
- scientific claims de alto impacto devem preservar source/caveat/approval quando necessário.

Ver `docs/12_KNOWLEDGE_INGESTION_AND_RETRIEVAL.md`.

## Current known security findings — 2026-08-22

Observados diretamente no projeto Supabase durante auditoria de leitura:
- múltiplas tabelas com RLS habilitado porém sem policies;
- funções SECURITY DEFINER acessíveis a `anon`/`authenticated` no schema público;
- funções com mutable search_path;
- extensões instaladas em `public`;
- leaked password protection desabilitado;
- Edge Functions públicas (`verify_jwt=false`) que dependem de mecanismos próprios de autenticação;
- diferença entre código versionado e funções publicadas.

Esses achados são **backlog obrigatório antes de go-live**, mas não devem ser corrigidos oportunisticamente no meio de outra migration sem plano.

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

### Classe F — agent behavior / prompt / model / retrieval
Pode parecer “só prompt”, mas pode alterar resultado de negócio.
Exige identificar behavior spec + eval cases relevantes e rodar regressão apropriada.

## Protocol before implementation

1. Ler `README_FIRST.md`.
2. Ler `00_EXECUTION_CONTROL.md`.
3. Identificar classe da mudança.
4. Verificar source of truth.
5. Verificar dependências/FKs/consumidores.
6. Determinar se muda arquitetura.
7. Identificar behavior/eval impact se agent-facing.
8. Se muda arquitetura: ADR + aprovação antes de código.
9. Implementar somente escopo pedido.
10. Testar acceptance criteria + regressions pertinentes.
11. Atualizar documentação/status.

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
- inventory de configs/content fora de migrations;
- compatibility view/RPC quando necessário;
- migration reversível ou recovery procedure;
- consumers migrated/tested;
- only then remove legacy.

## Protocol for behavior changes

Para prompt/playbook/model/context/retrieval/tool behavior:
- localizar `Behavior Spec` aplicável;
- localizar golden cases relevantes;
- registrar versões afetadas;
- implementar de forma estreita;
- rodar regressão;
- não editar expected behavior só para esconder regressão.

Ver `docs/13_EVALS_AND_OBSERVABILITY.md`.

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
- diferença entre contact point e external id?
- diferença entre product e product_run?
- onde preço é autoridade?
- quando RAG é inadequado?
- como agents acessam dados?
- qual behavior spec governa o agente?
- quais evals precisam passar?
- como outbound decide se pode contactar?
- quando preciso de ADR?

Se não souber, ainda não deve fazer alteração estrutural ou behavior-critical.