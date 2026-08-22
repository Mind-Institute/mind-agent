# MIND INTELLIGENCE — CURRENT STATE SNAPSHOT — 2026-08-22

Este documento registra o que foi observado diretamente no Supabase e GitHub antes da migração. Não substitui o checkpoint técnico; serve como mapa arquitetural do estado atual.

## Repository state

Repository: `Mind-Institute/mind-agent`.

A branch `claude/mind-chatbot-treble-6bbu4a` contém a pasta `supabase/`, incluindo `migrations/` e `functions/`.

O `main` não refletia todo o estado atual do Supabase no momento da auditoria.

Na branch observada, estavam versionadas principalmente as Edge Functions:
- mindagent-sync-precos
- treble-api
- treble-inbound-agent

No Supabase, estavam publicadas 8 Edge Functions:
- mindagent-bootstrap
- treble-find-location
- mindagent-admin
- mindagent-chat
- treble-agent
- mindagent-sync-precos
- treble-inbound-agent
- treble-api

Conclusão: código versionado e runtime publicado não estavam completamente sincronizados.

## Checkpoint concluído

Branch:
`checkpoint/pre-mind-intelligence-architecture`

Commit:
`372992ee22c32e1b0b6b300ad477b60ce41c3701`

Working tree: clean.

Capturado:
- as 5 Edge Functions que estavam publicadas mas não versionadas foram recuperadas da produção;
- as 3 Edge Functions já versionadas foram preservadas;
- 33 migration files existentes no repo foram preservados;
- ledger das 99 migrations aplicadas foi registrado;
- nenhum deploy/merge/mutação no Supabase ocorreu durante o checkpoint.

### Gaps do checkpoint

1. `database-schema.sql` não foi gerado porque `supabase db dump` exigia conectividade ao Postgres/API bloqueada pelo proxy do ambiente.
2. 99 migrations estão aplicadas no banco, mas apenas 33 migration files existem no repo; 71 applied migrations não possuem arquivo correspondente e seus statements existem apenas no ledger do banco.
3. Configuração/conteúdo curado fora de migrations precisa ser preservado antes de qualquer destruição, incluindo:
   - `treble.prompts`;
   - `treble.config`;
   - `summit.commercial_rules`;
   - `summit.offers`;
   - `engagement.origens`;
   - `crm.mapa_produtos`.
4. Secrets das Edge Functions não são recuperáveis pelo checkpoint; apenas nomes são conhecidos.
5. Bucket `mind-assets` não foi incluído no checkpoint.

Esses gaps são hoje parte explícita do risco de migração.

## Database migration history

O projeto acumulou muitas migrations entre 2026-08-20 e 2026-08-22, incluindo:
- bootstrap inicial de schema/ciclo/privacidade/jornada/LLM;
- camada Mind Intelligence experimental;
- event navigation/offers/agent API e rollback;
- Treble read layer;
- admin/content operations;
- mindagent chat backend/auth/interests;
- Treble inbound/agent/handoff;
- pricing/lotes;
- prompts modulares;
- origens/UTM/materiais;
- speakers/programação;
- catálogo de produtos;
- CRM pessoas/sync/contexto;
- sequência de “faxina” de schemas/pessoa/concierge/comum/conhecimento.

Essa história mostra evolução rápida/prototipagem. Não assumir que nomes atuais representam decisões arquiteturais definitivas.

## Current product/catalog model

Existe `catalogo.produtos` com itens como:
- Mind
- Mind Dash
- Mind Institute
- produtos/turmas de Institute 2025
- Mind Journey 2025
- Oxford no Conselho
- Mind Summit 2025
- Mind Summit 2026

Problema arquitetural:
`catalogo.produtos` mistura canonical products e concrete runs/editions.

Target:
- `catalog.products`
- `catalog.product_runs`

## Current person model

`crm.pessoas` funciona hoje como pessoa universal de facto.

Foi observado `engagement.v_pessoa` como view sobre `crm.pessoas` + perfil/identidades.

Muitas foreign keys de Concierge, Engagement, Intelligence, Summit e Treble apontam diretamente para `crm.pessoas`.

Exemplos de dependentes:
- concierge.ciclo_estado
- concierge.ferramenta_chamadas
- concierge.integracao_logs
- concierge.proativo_fila
- crm.acessos
- crm.consents
- crm.pessoa_nps
- crm.pessoa_produtos
- engagement.agent_sessions
- engagement.conversas
- engagement.mensagens
- engagement.feedbacks
- engagement.jornada_sessao
- engagement.nps
- intelligence.participante_contexto
- intelligence.participante_memoria
- intelligence.participante_objetivos
- intelligence.recomendacoes
- intelligence.sinais_comerciais
- summit.registrations
- summit.session_reservations
- treble.conversations

Conclusão:
Migrar canonical person para `people.people` é mudança coordenada Classe D. Não fazer rename improvisado.

### Identity/contactability implications

O protótipo já possui partes de identidade e consent/consents espalhadas, mas o target precisa distinguir explicitamente:
- canonical person;
- human contact points (email/phone/WhatsApp-like identifier);
- provider external refs;
- CRM relationship;
- consent/contactability/suppression.

Isso é necessário antes de outbound para evitar retrofit estrutural.

## Current conversation/runtime split

Existem dois modelos principais de conversa.

### Concierge/web
- `engagement.agent_sessions`
- `engagement.conversas`
- `engagement.mensagens`
- `engagement.session_interests`
- device/auth/session logic

Edge Function `mindagent-chat` usa esse modelo.

Pontos fortes observados:
- Supabase auth/session validation;
- device/session token;
- bind identity por email;
- profile loading;
- message persistence;
- interest extraction com confidence/confirmed;
- official search context.

### Sales/Treble
- `treble.conversations`
- `treble.messages`
- `treble.conversation_interests`
- `treble.prompts`
- `treble.config`

Edge Function `treble-inbound-agent` usa esse modelo.

Pontos fortes observados:
- Treble payload handling;
- dedup de webhook;
- attribution/origem/UTM;
- commercial context;
- price guardrails;
- audience/intent/ticket interest/objection/stage structured output;
- response returned as Treble session keys;
- prompt composition by audience;
- group pricing logic;
- checkout attribution.

Problema arquitetural:
Sales e Concierge têm runtimes e stores paralelos. Target deve preservar os melhores comportamentos de ambos em um core compartilhado.

Importante: core compartilhado não exige uma única conversation infinita. A mesma pessoa pode manter conversations distintas por canal, ligadas pela mesma identity/intelligence/summaries.

## Current Summit model

Schema Summit já contém componentes úteis e dados reais, incluindo:
- events
- venues
- locations
- sessions
- session_speakers
- exhibitors
- offers
- coupons
- commercial_rules
- registrations
- reservations
- polls
- routing/navigation
- knowledge documents/chunks

Programação e speakers foram populados a partir de planilhas recentes.

Target:
- manter domain-specific event depth em `summit`;
- normalizar edition para `product_run` facet;
- mover pessoas globais para `people`;
- mover offer/pricing/discount truth para `commercial`.

## Current speaker model

`comum.speakers` é consumido por Summit sessions e search.

Problema:
“speaker” é papel contextual, não identidade global.

Target:
- `people.people`
- profiles/works/affiliations
- summit edition/session roles pointing to canonical people.

## Current commercial model

`summit.offers` e RPCs públicas carregam boa parte da verdade comercial.

Funções observadas:
- `mind_precos_por_volume()`
- `mind_virada_de_lote()`
- `mind_checkout_url()`
- `treble_agent_context()`
- `mindagent_sync_offers()`

O Sales runtime só aceita preço oficial presente no contexto ou total derivado de preço unitário oficial, evitando preço inventado.

Esse comportamento deve ser preservado.

Target:
`commercial.offers`, pricing_periods, offer_prices, offer_inclusions, discount_rules, orders etc.

## Current Agent/API layer

Já existem muitas RPCs públicas/API experimentais, por exemplo:
- api.changed_since
- api.contact
- api.event
- api.knowledge
- api.me
- api.mindagent_bootstrap
- api.my_agenda
- api.my_context
- api.sessions
- api.speakers
- api.treble_event_bundle
- api.treble_find_location
- api.treble_route
- crm.buscar_pessoa
- crm.contexto_comercial
- public.mindagent_chat_*
- public.mindagent_treble_*
- public.treble_agent_*

Conclusão:
Há bastante lógica reaproveitável, mas o target deve consolidar contratos semânticos em `agent_api` e remover dependência de funções públicas ad hoc conforme consumers migram.

## Current knowledge model

Há knowledge documents/chunks distribuídos por `comum`, `summit`, `institute`, `dash`, `eventos`, com views union em `mind`.

Isso já expressa uma tentativa de separação por linha, mas target diferencia:
- structured operational truth;
- canonical people/product entities;
- knowledge científico/global estruturado;
- product content/editorial;
- product-specific documents quando necessário.

O target não deve simplesmente consolidar tudo em um vector index único.

Não apagar antes de mapear conteúdo útil e consumers.

## Current behavior/eval maturity

O protótipo possui structured outputs, prompts modulares e guardrails comerciais úteis, mas ainda não possui uma camada suficientemente explícita de:
- Sales Behavior Spec;
- golden conversation suite;
- hard-failure regressions;
- context/retrieval trace;
- eval-driven acceptance por mudança de prompt/model/playbook/retrieval.

Esses elementos passam a fazer parte do target antes da migração do Sales runtime.

## Security findings observed

Supabase advisor report indicou, entre outros:
- várias tabelas com RLS enabled but no policy;
- mutable search_path em funções públicas;
- extensions em public;
- SECURITY DEFINER functions executáveis por anon/authenticated;
- anonymous access policies em cron;
- leaked password protection disabled.

Também existem Edge Functions com `verify_jwt=false`; algumas usam token/query secret próprio, outras precisam de revisão individual.

Nada disso deve ser corrigido aleatoriamente durante documentação/migração; é backlog obrigatório de hardening antes de go-live.

## Current architectural diagnosis

### Preserve behavior/data
- Treble webhook/adapter logic
- Sales commercial guardrails
- Sales prompts/playbook content useful as source material
- Concierge auth/session/identity patterns
- Summit agenda/sessions/spaces data
- speakers data
- pricing/volume/checkout logic
- attribution/UTM logic
- existing webhook contracts
- curated config/content identified in checkpoint

### Rebuild/unify architecture
- canonical person/contact point model
- privacy/contactability/suppression
- conversation/message core
- intelligence model
- catalog product/run distinction
- commercial shared domain
- agent runtime/profile/tool architecture
- semantic Agent API
- source-of-truth governance
- knowledge ingestion/retrieval governance
- evals/observability

### Likely remove after migration
- duplicate/parallel runtime tables/functions
- legacy Treble agent versions no longer consumed
- ad hoc overlapping person/interest structures
- compatibility functions after all consumers migrate

No legacy structure may be dropped merely because it looks duplicate. Confirm consumers/FKs/runtime/config/recovery first.

## Current operational principle

The current system is a prototype, not an architectural contract.

**Preserve useful behavior, data and configuration. Do not preserve accidental topology.**