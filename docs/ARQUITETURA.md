# Mind Intelligence — arquitetura real

> O que o sistema **é hoje**, não o que uma IA imaginou. Fonte da verdade: banco real
> (`mind-agent`, Supabase). Quase tudo é teste/placeholder — dá pra remodelar à vontade.

## O que estamos construindo

Três agentes sobre um mesmo núcleo compartilhado:
- **Vendas** — conduz oportunidade comercial (qualquer vertical) e atualiza o HubSpot.
- **Atendimento** — pós-venda / suporte de quem já comprou.
- **Concierge** — embarcado no app do MindSummit; ajuda quem está no evento.

### Como um agente é montado
`prompt base` (comum a todos, em `agentes`) **+** `prompt da plataforma` (`concierge` p/ o
app, `treble` p/ WhatsApp) **+** `playbook da função` (vendas / atendimento / concierge —
independentes) **+** `contexto do produto` buscado na hora.

O vendedor vende Summit, Dash ou Institute com **o mesmo** playbook de vendas — muda só o
**contexto do produto** que ele busca. Playbooks vivem em `agentes.prompts` (por `chave`), por função.

### Onde mora a conversa e a inteligência de QUALQUER agente (regra de plataforma)
O núcleo é **um só e compartilhado** entre todos os agentes; muda só a **plataforma** (por onde
a pessoa fala) e a **função**. Quando nasce um agente numa plataforma nova (site, Instagram,
e-mail, telefone…), NÃO se cria um mundo à parte pra ele. A divisão é sempre esta:
- **Config da plataforma** → schema só de config (como `treble` p/ WhatsApp, `concierge` p/ o app):
  token, modelo, templates, flags. **Conversa não mora aqui.**
- **A conversa** (mensagens trocadas) → **SEMPRE** `engagement.conversas` + `engagement.mensagens`,
  com a coluna **`agente`** dizendo quem escreveu (ex.: `treble-inbound-agent`). Uma casa só pra
  todos. **Nunca** `treble.messages`, `concierge.mensagens`, `plataformaX.conversas`.
- **O que o agente APRENDE** com as mensagens (sinal, intenção, objeção, dossiê) → **SEMPRE**
  `intelligence.*`, marcando de qual agente veio. **Nunca** inteligência apartada por plataforma.
- **Quem a pessoa é** → `pessoas.pessoas` (identidade única); os canais dela → `engagement.identidades`.

Motivo: se cada plataforma tiver a sua tabela de conversa/inteligência, o vendedor do WhatsApp
não enxerga o que o concierge do app já sabia — a inteligência do Mind vira ilha. Detalhe completo
e o "antes de criar tabela, pergunte" estão no `README_FIRST.md`.

### O que acontece quando um lead chega
1. Identifica a pessoa e registra que ela chegou (e por onde) em `pessoas.pessoas`.
2. Deriva a **vertical** de onde veio: `intelligence.vertical_da_entrada(site, url)`
   (site do chat ou domínio do `first_url`) → grava em `intelligence.sinais_comerciais.vertical`.
3. Junta o que já se sabe dela, antes de responder:
   - histórico de vida no Mind → `crm.contato_espelho` + `crm.negocios_historicos`;
   - deal **aberto** agora → `crm.pipeline_summit_leads_captados` (e pipelines futuros por vertical).
4. Atua com o playbook da função; se for venda, ao fechar atualiza o card do pipeline /
   cria caso e reflete no HubSpot.
5. Destila **inteligência** sobre a pessoa (`intelligence`) e registra o **engajamento**
   (`engagement`) — enriquecendo o que sabemos dela a cada conversa.

## Mapa dos schemas (o que é real × teste × futuro)

**Núcleo do lead**
- `pessoas` — identidade canônica (1 linha = teste).
- `crm` — espelho do HubSpot. **REAL:** `contato_espelho` (11.587), `negocios_historicos`
  (7.092), `pipeline_summit_leads_captados` (2.675 = pipeline aberto), `mapa_produtos` (9).
- `intelligence` — o que sabemos do lead (sinais, intenções, dossiê, objetivos…). Teste/placeholder.
- `engagement` — conversas/mensagens/sessões. Dados de teste. A **origem do lead na chegada**
  é salva aqui (`origens`, provisório — a confirmar). *(candidato a virar vizinho de/parte de `intelligence`.)*
  A conversa do WhatsApp/Treble também mora aqui: `conversas` + `mensagens`, com a coluna
  `agente` marcando de qual agente veio a info (hoje `treble-inbound-agent`; haverá outros).
  O estado solto da venda (intent, objeção, needs_human, checkout, desfecho) fica em
  `conversas.variables` (jsonb) — sem coluna nova por campo.

**Verdades transversais**
- `ecossistema` — universais: `palestrantes_especialistas` (13). *(catálogo e políticas devem vir pra cá.)*
- `catalogo` — mapa vertical→produtos→pipeline: `produtos` (11). *(alvo: dentro de `ecossistema`.)*
- `agentes` — `prompts`: prompt base, playbooks e tom de voz, por `chave`
  (`playbook_router`, `playbook_summit_b2b`, `playbook_summit_b2c`, `playbook_cliente_suporte`,
  `tom_de_voz`). É AQUI que vivem os playbooks — não criar tabela separada.
- `platform` — infra de LLM: providers/models/routes + integrações. Real, útil.

**Verticais de produto** (produtos/ofertas + pipeline de cada frente)
- `summit_2026` — **RICO:** 67 sessões, 61 speakers, 27 locais, 25 ofertas (Prime/VIP/Mind,
  delegações, patrocínios), 17 docs. É a inteligência do evento deste ano.
- `institute` (formações), `dash` (consultoria), `eventos` (promocionais) — **vazios**,
  placeholders para o futuro. Tudo bem ficarem vazios.

**Plataformas dos agentes**
- `concierge` — config/inteligência do agente embarcado no app do Summit (templates, ferramentas, flags).
- `treble` — config dos agentes no WhatsApp (Treble). Catálogo de fluxos em `treble.polls`;
  status aberta/fechada por número em `treble.status_da_conversa`. Fluxo completo (janela de 24h
  → HubSpot, pra não disparar em cima de conversa aberta): ver **`docs/TREBLE_STATUS_24H.md`**.

## Reconhecimento do lead — LEITURA, não cópia
Na chegada, o "dossiê" do lead é **montado por uma função que LÊ** (estende `crm.buscar_pessoa`),
**não** uma tabela nova. Nunca copiar histórico pra `pessoas`/`intelligence` (duplica e envelhece).
Papéis: `pessoas.pessoas` = identidade; `crm.*` = histórico/deals (lido ao vivo); `intelligence.*`
= o que o agente **aprende** (escrito depois); `engagement` = origem (`origens` catálogo +
`utm_sessoes` evento do lead) + conversas.
**Chave de join = email** → `crm.contato_espelho.hubspot_id` → **`crm.negocio_contatos`** (view:
relação deal↔contato derivada de `propriedades->_contatos`; 100% casa com o espelho) → os **deals
da pessoa**. Já funciona pros 2 pipelines espelhados: `default` (histórico, `negocios_historicos`)
e `917379159` (summit, `pipeline_summit_leads_captados`). `pessoa_id` segue NULO nesses espelhos
(ligamos por hubspot_id/email, não por pessoa_id). Pipelines ainda NÃO espelhados no Hub precisam
de sync (tabela por pipeline).

## Silence Re-evaluation Engine — quem manda no relógio  ⏸️ *pausado em 28/08*

> **Estado:** construído e testado, mas o cron `silence_reavaliar` (job 13) está **desligado** —
> ninguém acorda ninguém. O `silence_sync_from_analysis` segue ligado (só mantém o estado em dia,
> sem IA). Religa com `select cron.alter_job(13, active := true);`.
> As decisões pendentes estão em **BACKLOG item 2**.


Duas coisas diferentes que costumam ser confundidas: **REVIEW ≠ FOLLOW-UP.** Review é o sistema
acordar a oportunidade e *olhar* pra ela. Follow-up é falar com a pessoa. Toda review olha; nem
toda review fala.

**A divisão de trabalho:** a IA lê o estado comercial e decide *o quê*
(`ACT | WAIT | ESCALATE | DORMANT | STOP`). O **código** decide *quando* — a IA nunca escolhe
timestamp, e `NEXT_REVIEW_AT` nem aparece no schema de saída dela.

**Onde mora:** `intelligence.continuidade_comercial` (1 linha por conversa; PK `conversa_id`).
Guarda `continuation_status`, `next_review_at`, `next_review_policy`, `followup_count`,
`last_followup_at`, `last_decision` (decisão + cálculo, pra auditar) e `processing_until` (lock).

**Configuração do relógio:** `intelligence.config` chave `silence_timing_v1` — a matriz da seção 7
do playbook (1ª revisão: critical 30min · very_high 90 · high 180 · medium 360 · low 1440;
depois de follow-up, uma lista por chave; estourou a lista → `DORMANT`). Mudar o ritmo é mudar
esse JSON — não é mexer em código nem em prompt.

**Precedência (nesta ordem, e ela existe pra proteger a pessoa):**
1. compra (no CRM ou declarada), opt-out, `STOP`/`STOPPED` → não agenda nada;
2. `DORMANT` → sai da fila, só volta por evento;
3. `ESCALATE` com dono humano → pausa (o humano assumiu);
4. **sem open loop real → não agenda.** Silêncio sozinho não autoriza follow-up;
5. compromisso com data real → o compromisso manda;
6. senão, matriz determinística ancorada no **último evento da conversa** (nunca em `now()`).

**Duas travas que só existem porque o teste real mostrou que precisavam:**
- **Piso temporal.** Sem ele, conversa parada há dias reagendava sempre no passado e era
  reavaliada em loop a cada rodada do cron. Numa reavaliação o próximo passo é sempre no futuro,
  usando o mesmo intervalo da matriz.
- **Compromisso só com data real.** Quando o lead falou vago ("acho que respondem essa semana"),
  a reavaliação chutou 27/08 numa rodada e 31/08 na outra — a IA escolhendo o relógio pela porta
  dos fundos. Data de compromisso só vale se veio do analisador, que lê o que a pessoa
  efetivamente disse. Compromisso sem data é open loop, e quem manda nele é a matriz.

**As peças:** `silence_calcular_next_review` (o relógio, não grava nada) ·
`silence_sync_from_analysis` (chamada pelo `analise_gravar`, monta o estado) ·
`silence_claim_pendentes` (`FOR UPDATE SKIP LOCKED` + lock de 10 min) · `silence_registrar_decisao`
· `silence_compra_summit_2026` (`purchased`/`not_purchased`/**`unknown`** — na dúvida, `unknown`) ·
edge `silence-reavaliar` + cron a cada 5 min.

**Hoje ela NÃO envia mensagem** — decisão da Adriana. `ACT` vira registro, e por isso
`followup_count` não sobe: contar tentativa sem falar com ninguém queimaria as 3 retomadas do
playbook em silêncio. Quando a camada de envio existir, ela passa
`p_followup_enviado := true`. Ver **BACKLOG item 2**.

## Schemas do sistema (do Supabase — não são design nosso, ignorar)
`auth`, `storage`, `supabase_migrations` (histórico de migrations), `vault` (segredos),
`net`/`pg_net`, `pgbouncer`, `realtime`, `cron`, `extensions`, `graphql`/`graphql_public`
(GraphQL do PostgREST — não usamos, pode ignorar).

## Limpeza / pendências
- `quarentena` — **removido** (lixo).
- `mind` — `policies` (6) devem ir p/ `ecossistema`; `organization_content` vazio. Depois `mind` some.
- `public` — só tem o backend do painel admin (`mind_admin_*`); ideal mover p/ schema `admin`.
- **Faxina** de `engagement`+`intelligence` (feedback espalhado em 6 tabelas, perfis
  duplicados) — decidir tabela a tabela o que fica; são as casas da saída dos agentes.
- **Edge functions** (12) — inventariar e remover os mortos (`*-diag`); manter `hubspot-sync`,
  `treble-inbound-agent`, `mindagent-chat`.
