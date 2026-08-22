# MIND INTELLIGENCE — AGENT RUNTIME, CONTEXT & MEMORY

## Purpose

Define como um turno deve fluir, como agents recebem contexto, como memória é persistida, como autoridade/freshness é preservada e como delegação/ações funcionam.

## Runtime físico esperado

```text
TREBLE / APP / SITE
        |
        v
Edge Function orchestrate-turn
        |
        v
Database Functions / RPCs
(build context / semantic reads)
        |
        v
prepared context + context manifest
        |
        v
LLM
   |            |
response      tool call
                |
                v
          tool executor
                |
                v
               LLM
                |
                v
             response
                |
                v
           memory loop
                |
                v
          queue/background
```

## Synchronous turn pipeline

1. Receber webhook/request.
2. Validar auth/origem.
3. Idempotency/dedup.
4. Persistir raw message.
5. Resolver pessoa e contact/external identifiers.
6. Resolver entry context e product scope.
7. Triage intent/capability/profile.
8. Build Base Context.
9. Context Planner identifica gaps.
10. Agent API busca apenas o necessário.
11. Registrar context manifest/retrieval trace suficiente para reprodutibilidade operacional.
12. Carregar playbook e policies aplicáveis.
13. Decisioning escolhe move/next action.
14. Agent gera resposta e/ou tool call.
15. Tool executor executa apenas ação autorizada.
16. Persistir run/decision/action/response.
17. Retornar ao canal.

A resposta do WhatsApp não deve bloquear em trabalho pesado que pode ser posterior.

## Background path

Depois da resposta, enfileirar quando apropriado:
- extract-turn-intelligence;
- consolidar facts;
- atualizar summaries;
- recalcular product_fit;
- sync HubSpot;
- evaluate-opportunity;
- embeddings;
- follow-up evaluation;
- outras ações outbox.

## Orchestrator

Responsabilidades:
- receber canal;
- resolver identity;
- escolher profile;
- montar contexto;
- chamar modelo;
- executar tools;
- retornar resposta;
- registrar execução;
- enfileirar background.

Não deve conter toda a lógica de negócio hard-coded.

## Tool executor

LLM vê tools semânticas. Tool executor mapeia tool → RPC/database function/external integration.

Exemplo de organização:
`supabase/functions/_shared/tools/`

Cada tool deve ter:
- nome semântico;
- input schema estreito;
- output previsível;
- permission/action scope;
- idempotency quando escreve;
- audit trail quando produz efeito externo;
- authority/freshness metadata quando relevante.

## Profiles

### sales_summit
Auto context:
- person;
- CRM relationship;
- relationship/commercial summary;
- recent messages;
- active intelligence;
- Summit 2026 scope;
- current offer/price when relevant;
- effective sales playbook.

Discoverable:
- Institute;
- Dash;
- relevant science;
- old history.

Capabilities:
- sell;
- recommend;
- handle_objection;
- qualify;
- record_intelligence;
- follow-up;
- delegate research;
- handoff human.

Behavioral source of truth: `docs/11_SALES_AGENT_BEHAVIOR_SPEC.md`.

### concierge_summit
Auto context:
- person;
- access/ticket if known;
- personal agenda;
- reservations;
- attendance;
- interests/feedback;
- current event agenda/sessions/speakers/location.

Capabilities:
- answer event questions;
- recommend sessions;
- reserve/cancel if authorized;
- record feedback;
- send materials;
- identify opportunity;
- handoff.

### service_default
Auto context:
- person;
- purchases;
- access rights;
- tickets;
- history;
- goals;
- health/risk/opportunity.

### researcher_scientific
Auto context:
- question;
- relevant concepts;
- source requirements;
- evidence/citation policies.

Broader knowledge scope; no default authority to change CRM/commercial state.

## Context Planner V1

Não criar outro mega-agent no início.

Pode ser:
- regras determinísticas;
- ou structured output curto no mesmo/primeiro LLM call.

Output conceitual:
```json
{
  "needs": ["commercial.current_offer", "summit.sessions_by_topic"],
  "needs_deep_research": false,
  "needs_old_history": false
}
```

## Decisioning V1

Pode ocorrer na mesma chamada que gera resposta, desde que structured output capture:
- current_stage;
- objective;
- selected_move;
- next_best_action;
- confidence;
- user-facing answer;
- tool/action requests.

Só separar em serviço/modelo próprio se evals mostrarem necessidade.

## Memory model

### Facts
Objetivamente conhecidos e verificáveis.

Regra: não duplicar fatos que já possuem representação canônica apropriada. Email/telefone ficam em `people.contact_points`; compra em `commercial`; affiliation em `people.affiliations` ou CRM conforme semântica.

### Insights
Inferências úteis.
Ex.: objection=time; buying_signal=team_interest; preference=workshop_practical.

Sempre com source/confidence/provenance.

### Intents
Sinais transitórios de routing.
Ex.: sales_b2b, event_navigation, support, purchase_ready.

### Summaries
Compressão de relação, não substituto da evidência.
Cada summary deve indicar até que ponto do histórico representa (`valid_through_at`).

### Product fit
Score/razão para produto/run com evidência.

## Memory loop behavior

Cada conversa deve melhorar a próxima sem acumular lixo.

Regras:
- não salvar todo substantivo como interesse;
- não inferir atributo sensível;
- preferir categorias estáveis;
- permitir supersession/invalidation;
- manter evidência de origem;
- separar explicit confirmation de inferred signal;
- summaries devem ser refresháveis;
- não duplicar dados canônicos em `facts`.

## Conversation model across channels

`engagement` é compartilhado, mas uma pessoa pode ter múltiplas conversations:

```text
PERSON
 ├─ WhatsApp conversation
 ├─ App conversation
 ├─ Site conversation
 └─ Human conversation
        ↓
shared intelligence
shared summaries
shared relationship
```

A continuidade entre canais vem da pessoa e da memória compartilhada, não de uma conversa infinita única.

## Identity resolution

Desired order:
- trusted external id when mapped;
- verified/normalized contact point;
- known auth/user account;
- explicit merge resolution for ambiguity.

`people.contact_points` guarda meios/identificadores humanos de contato.
`integrations.external_refs` guarda ids externos de Treble, HubSpot, Eduzz etc.

Não criar pessoa nova para cada canal.

## Entry context

Entry context deve sobreviver ao canal e orientar primeira resposta.

Exemplos:
- veio de abandono PRIME;
- veio de botão “delegação corporativa”;
- veio de página de programação;
- veio de campanha específica;
- UTM/referrer/landing page.

Router não deve perguntar “o que você quer?” se o sistema já sabe com boa confiança por onde a pessoa entrou.

## Router

Deve ser simples:
- resolve identity;
- record entry context;
- detect current intent;
- infer likely product scope;
- update immediately relevant signals;
- choose profile/capability.

Não virar um agent de negócios gigante.

## Context authority/freshness

Contexto entregue ao modelo deve conseguir distinguir, quando necessário:
- authoritative;
- observed;
- inferred;
- generated;
- freshness/validity;
- confidence;
- sensitivity.

Exemplo: preço oficial não deve parecer equivalente a “lead parece sensível a preço”.

Detalhes: `docs/12_KNOWLEDGE_INGESTION_AND_RETRIEVAL.md`.

## Delegation

`delegate_task()` permite specialist profile sem trocar necessariamente a persona visível.

Researcher deve devolver resposta estruturada:
- answer/synthesis;
- sources;
- caveats;
- confidence/limitations quando aplicável.

## Human handoff

Handoff deve registrar:
- reason;
- current context summary;
- relevant messages;
- urgency;
- owner/team quando conhecido;
- whether agent should resume later.

## External effects

Ações como criar task, mandar email, atualizar CRM devem:
- ser explicitamente autorizadas pelo profile/action scope;
- ser idempotentes;
- registrar audit/event/outbox;
- tratar retries sem duplicar efeito.

Para outbound, nenhuma decisão do LLM substitui contactability/consent/suppression determinísticos. Ver `docs/14_OUTBOUND_WORKFLOW.md`.

## LLM observability

`agents.runs` deve permitir rastrear:
- profile/version;
- model/provider;
- prompt version;
- playbook version;
- context profile version;
- tool calls;
- latency;
- status/error;
- referenced decision/action ids;
- evaluation linkage.

Não é necessário guardar chain-of-thought.

## Context manifest / retrieval trace

Cada run deve poder registrar o que efetivamente foi usado/retrieved:
- tool/function;
- record/source ids;
- authority/freshness;
- version/hash quando útil;
- query/filter descriptor seguro;
- latency;
- included_in_final_context.

Objetivo: reproduzir operationalmente por que determinado dado chegou ao modelo sem armazenar raciocínio privado.

## Evals as part of runtime development

Evals começam antes do primeiro agent e acompanham mudanças de prompt, playbook, context profile, retrieval, model e tools.

Ver `docs/13_EVALS_AND_OBSERVABILITY.md`.

## Anti-patterns

- Um Edge Function diferente contendo uma arquitetura completa para cada agent.
- Cada canal com suas próprias tabelas de person/intelligence.
- Forçar todos os canais numa conversation infinita única.
- Prompt gigante com todos os preços/sessões/speakers.
- LLM escolhendo tabelas/SQL diretamente.
- Interest/pain/objection virando colunas ad hoc em conversation.
- `intelligence.facts` virando duplicata do banco inteiro.
- Agent respondendo antes de persistir/claim idempotency quando webhook pode repetir.
- Background enrichment bloqueando WhatsApp.
- Researcher sendo chamado em todo turno.
- Não registrar contexto/retrieval suficiente para investigar uma resposta ruim.

## MVP acceptance test

O skeleton só é considerado funcional quando:
1. uma pessoa conversa;
2. identity é resolvida;
3. mensagem é persistida;
4. contexto correto é recuperado;
5. resposta usa dados oficiais;
6. insight/intent relevante é persistido;
7. pessoa volta depois;
8. agent lembra da relação sem reiniciar a conversa;
9. run pode ser auditado por versões + context/retrieval trace;
10. golden evals críticos continuam passando.