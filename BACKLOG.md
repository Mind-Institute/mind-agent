# Backlog — fila de desenvolvimento

Este arquivo preserva **trabalho conhecido que ainda não foi feito e investigação já realizada que não pode se perder**.

Para reconstruir o projeto sem contexto, a ordem obrigatória de leitura é:

1. `PROJECT_STATE.md` — arquitetura congelada, ordem de execução, versões e checkpoint atual;
2. `BACKLOG.md` — o que ficou para depois e o que já sabemos sobre cada frente;
3. `docs/CORE_UNIVERSAL.md` — estado real e contratos implementados.

## 0. Índice da execução até o fim do Core Universal

O significado detalhado, as decisões congeladas e o runtime estão em `PROJECT_STATE.md`. Este índice fica aqui também para ninguém abrir o backlog e perder a sequência.

| # | passo | estado |
|---|---|---|
| 1 | Ingestão + persistência + identidade universal | ✅ fechado |
| 2 | Ponte Pessoa Mind ↔ CRM/HubSpot | ✅ fechado |
| 3 | Fila universal de resolução identidade/CRM | ✅ fechado |
| 4 | Coletor factual CRM | ✅ fechado |
| 5 | Compras + contexto comercial | ✅ 5A fechado |
| 6 | Coletor factual de Engagement | ✅ fechado |
| 6B | Normalização universal de áudio | ✅ fechado; risco de confiabilidade/latência fica deferido |
| 7 | Normalização determinística da pessoa | ✅ fechado |
| 8 | `AGENT_CONTEXT` universal | ✅ fechado |
| 9 | Testes de contrato do `AGENT_CONTEXT` | ✅ fechado |
| 10 | Router universal | ✅ fechado |
| 11 | Registry de rotas + Capability Gate | ✅ fechado |
| 12A | Auditoria/reforma Product Intelligence + Knowledge | ⏸️ parcial; 12A.1 concluído, restante investigado/deferido abaixo |
| 12B | Source Registry mínimo + Kit Loader universal | 🚧 passo atual — investigação enviada ao Claude |
| 13 | Finalizar cérebro de vendas Summit | ⬜ |
| 14 | Contrato universal de ação + handoff/escalation | ⬜ |
| 15 | Análise pós-turno + memória universal | ⬜ |
| 15B | Write-back + dispatch operacional pós-turno | ⬜ |
| 16 | Continuidade / Silence | ⬜ |
| 17 | E2E vendas Summit via Treble | ⬜ |
| 18 | Hardening + documentação + travas Core Universal | ⬜ |

### Regra para não perder decisões nem investigações

- Decisão marcada como **CONGELADA** deve ser registrada em `PROJECT_STATE.md`; conversa não é documentação.
- Mudança material em decisão congelada → nova versão do `PROJECT_STATE.md` (`vN → vN+1`) com o que foi substituído e por quê.
- Mudança implementada → atualizar as seções afetadas de `docs/CORE_UNIVERSAL.md` depois dos testes.
- Descoberta relevante que não será resolvida agora → acrescentar ao **fim deste backlog** antes de avançar.
- O registro deferido precisa conter evidência já levantada, estado atual, por que foi deixado para depois, gatilho/dependências e como retomar sem reinvestigar do zero.
- A cada passo executado, atualizar o check/status do roadmap e o checkpoint atual.

Prioridade corrente:

`Source Registry + Kit Loader mínimo → Intelligence comercial mínima Summit → Decisioning de vendas → Agent → ação/handoff → memória/write-back/continuidade → Treble E2E → vendedor funcionando`.

---

## ✅ RESOLVIDOS (ficam registrados como referência)

**Exclusão de disparo do Summit** — no ar. Quem clica **"Já comprei meu ingresso"** ou faz
**opt-out** ("sair"/"Descadastrar") é excluído:
- `summit__participacao_anual` tem **2026** → não escreve nada (já está na lista de compradores);
- não tem → escreve `status_summit_2026 = "Não engajou"`.
- **Trava absoluta:** `summit__participacao_anual` **nunca** é escrito. Só compra real marca aquele
  campo. Quem não tem `hubspot_id` tem o **contato criado no HubSpot pelo telefone** (busca antes,
  pra não duplicar) e aí é excluído. **40 contatos** processados.

**CTAs comerciais** — mapeadas em `engagement.origens` (todas produto `mind-summit-2026`):
`Quero saber mais` → `summit_exit_popup` · `Garantir meu ingresso` → `summit_garantir_ingresso` ·
`Informação sobre o evento` → `summit_info_evento` · `Ver condições` → `delegacoes_condicoes_wpp`
(reusou a origem que já existia; **se essa CTA não for de delegações, é só avisar que eu troco**).

**Espelhos de outros Supabase da casa** — no ar (28/08). **9 fontes, 2 projetos de origem**,
carga completa em ~5 s, cron job 14 (`:20` e `:50`):

| origem | fontes | destino |
|---|---|---|
| `mind-summit-vendas-dashboard` | blinket (3.220) · vendas (3.207) | `eduzz.*` |
| | cred_participantes (1.028) · yazo_fila (4.026) · yazo_espelho (378) · yazo_sync_state (1) | `credenciamento_summit_2026.*` |
| `mind-hubpost` | produtos (290) · produto_catalogo (169) · hubspot_stage_config (21) | `eduzz.*` |

**Este projeto não fala com a Eduzz nem com a Yazo:** quem fala são os projetos de origem, que já
sincronizam sozinhos. O mind-agent espelha o espelho, por uma porta só de leitura
(`espelho_para_mind`, `SECURITY DEFINER`, segredo próprio no Vault de cada origem). A
`EDUZZ_API_KEY` guardada aqui **não abre nada**: não existe app OAuth pra conta 14449348
(`/oauth/token` → `App not found`). Pra puxar direto daqui um dia, tem que **criar um app OAuth na
Eduzz** — não adianta procurar a chave certa.

`pessoa_id` é **junção**, não coluna (views `eduzz.v_ingressos` / `v_vendas` /
`credenciamento_summit_2026.v_participantes`), pra ressincronização não apagar a ligação.
**1.352 pessoas já têm ingresso ligado.** Histórico de vendas confirmado **completo** contra a
própria Eduzz (`totalItems: 3185` para 2019–2026).

Duas decisões de encanamento que valem registro: o prefixo `eduzz_` saiu das funções e a tabela de
estado saiu de `eduzz.sync_estado` para **`public.espelho_estado`** — o mecanismo já serve dois
schemas, e deixar credenciamento dentro do schema da Eduzz confundiria quem chegasse depois. E a
coluna **`password`** do credenciamento **não é espelhada**: o corte é feito na porta da origem,
então o valor nem cruza a rede. Todas as tabelas espelhadas com **RLS ligado e zero policy**.

**Entrada de telefone** — normalização canônica `public.telefone_normalizar()` + gatilhos em
`pessoas.pessoas`, `engagement.conversas` e `treble.status_da_conversa`. Conserta o 9 do celular
(regra determinística: 8 dígitos começando em 6-9 = celular sem o 9), prepende DDI, devolve NULL
pro inválido. **3.432 números corrigidos**; era a causa das recusas do HubSpot.

---

## 2. Silence Engine — ⏸️ PAUSADO (28/08). O que precisa ser definido pra retomar

**Como está agora:** o motor está construído, testado (19 casos) e rodou de verdade em 14
oportunidades. O **cron `silence_reavaliar` (job 13) está DESLIGADO** — ninguém acorda ninguém,
zero chamada de IA, zero custo. Nada foi apagado.

**O que continua ligado de propósito:** o `analise_gravar` segue chamando
`silence_sync_from_analysis`. Isso só mantém o **estado** (status, próxima revisão) em dia
conforme novas conversas são analisadas — não usa IA, não decide, não fala com ninguém. Assim,
quando religar, a fila já está verdadeira em vez de desatualizada.

**Pra religar:** `select cron.alter_job(13, active := true);` — uma linha, volta do mesmo ponto.

### As 3 decisões que travam a continuidade (são suas, não minhas)

**D1 — `analise_vendas_summit` usa "stopped" com outro sentido.**
O Silence Playbook reserva `STOPPED` pra opt-out, recusa inequívoca, impossibilidade real
(seção 22). O analisador está devolvendo `continuation_status = "stopped"` com o sentido de
"a conversa acabou". Como a precedência manda não agendar nada pra quem está `STOPPED`,
**13 das 39 oportunidades nunca entram na fila** — inclusive uma com `purchase_intent = high`,
`commercial_priority = urgent` e compromisso em aberto ("retorno da gerência").
*Correção provável:* uma linha no seu prompt dizendo que `stopped` só vale pros casos da seção 22,
e que conversa que terminou com ponto aberto é `silence`. **É conteúdo, é seu — preciso do ok.**

**D2 — `DORMANT` com zero retomadas feitas.**
Na 1ª rodada real, uma oportunidade recebeu `DORMANT` com motivo `followup_exhausted` tendo
`followup_count = 0`. Nada foi esgotado. `DORMANT` tira a conversa da fila de vez (só volta por
evento), então errar aí perde a venda em silêncio. **Não travei no código** porque quem decide
*o quê* é a IA — sua regra. *Se você quiser:* recusar `followup_exhausted` quando o contador
está em 0. É uma linha.

**D3 — quem envia a mensagem, e sob qual autorização.**
Hoje `ACT` vira só registro em `last_decision` — tem **10 ACTs parados** esperando. Falta decidir:
- a mensagem sai automática ou passa por aprovação humana antes?
- sai por qual caminho — Treble (HSM/janela de 24h) ou outro?
- quem gera o texto final a partir do `message_brief` (Agent + Mind Voice)?
- qual janela de horário é permitida (o playbook prevê deslocar a execução, não a lógica).

Quando existir, essa camada chama
`silence_registrar_decisao(conversa, decisao, p_followup_enviado := true)`. É esse `true` que faz
o `followup_count` subir e o relógio pular pra régua de pós-follow-up. **Enquanto ele for `false`,
`DORMANT por followup_exhausted` nunca acontece de verdade** — o contador nunca sai de 0.

### O que NÃO precisa ser decidido (já resolvido, só pra não redescobrir)
- Ritmo de reavaliação: está em `intelligence.config → silence_timing_v1`. Mudar o ritmo é mudar
  esse JSON — não é código nem prompt.
- Compromisso com data: só vale data que o **analisador** extraiu do que a pessoa disse. A
  reavaliação não cria data (chutou 27/08 numa rodada e 31/08 na outra pro mesmo "acho que
  respondem essa semana"). Já barrou 2 casos.
- Loop de reavaliação no passado: resolvido com piso temporal.
- Compra: `purchase_confirmed_crm` (prova no banco) é distinto de `purchase_declared` (a pessoa
  disse na conversa). Ambos param o outreach; só o primeiro é prova. **Nada escreve no HubSpot.**

---

## 3. Prompts de análise que faltam

**Status:** conteúdo é da Adriana. Slots criados e vazios em `agentes.prompts`.

No ar: `analise_classificador` (v2) e `analise_vendas_summit` (v1).

Faltam — **e sem eles ~55% das conversas não são analisadas**, porque o classificador roteia pra lá
e não acha prompt ativo (nem o fallback):

- `analise_atendimento`
- `analise_concierge`
- `analise_contexto_geral` (fallback: se ativo, cobre qualquer conversa sozinho)
- `analise_vendas_institute` (nunca "instituto")
- `analise_vendas_dash`

---

## 4. Ranking ponderado — DECIDIDO: não volta por enquanto

**Status:** decidido (Adriana concordou). Nada a fazer.

A fórmula (conversa 40 · histórico 30 · fit de empresa 30) **não** volta agora. A priorização fica
com a taxonomia que o analisador devolve: `commercial_priority`, `purchase_intent`,
`conversion_risk`. Revisitar só se/quando o porte de empresa existir.

---

## 5. Porte da empresa (fit) via Lusha — DECIDIDO: não precisa agora

**Status:** decidido (Adriana). Fora de escopo até segunda ordem.

---

## 6. Lead no HubSpot: criar, atualizar propriedades e mover o estágio  ⭐ PRIORIDADE

**Status:** decidido que **vale a pena**; falta construir. **Promovido para o Passo 15B do roadmap**
(`Write-back + dispatch operacional pós-turno`, ver `docs/CORE_UNIVERSAL.md` §11) — deixou de ser
backlog. O detalhe abaixo continua valendo como levantamento para quando o 15B for construído.

Regra da Adriana: quando existe **oportunidade comercial**, o **card do lead tem que estar sempre
atualizado**. Isso significa três coisas, não uma:

1. **Criar o lead** no pipeline se a pessoa ainda não tiver card;
2. **Atualizar as propriedades** do lead com o que a análise aprendeu;
3. **Mover o estágio** do lead no pipeline (`hs_pipeline_stage`).

Propriedades de LEAD já mapeadas no HubSpot: `hs_lead_name`, `hs_lead_label` (status),
`hs_lead_type`, `hs_pipeline`, `hs_pipeline_stage`, `status_conversa` (a que já usamos),
`hs_lead_is_open`. Existe também uma de **observações** (a Adriana citou) — usar pro que **não
couber** em propriedade estruturada, ex.: `followup_anchor`, `conversation_summary`.

A fazer: mapear estado comercial da análise (`buyer_state`) → estágio do pipeline de leads;
escolher quais campos do `dados` viram propriedade; criar o card quando faltar; write-back
idempotente com trava (mesmo padrão de `crm.status_summit_hs`).

Uma regra que o 15B acrescenta: quando o produto **não tiver pipeline apropriado**, não se inventa
pipeline — persiste-se a inteligência e faz-se **dispatch para os responsáveis do produto**
(e-mail, follow-up, o que a operação daquele produto usar).

---

## 8. 19 funções ainda apontam pros schemas antigos (`summit.*` / `comum.*`)  ⚠️

**Status:** achado ao consertar o contexto do agente. **Não corrigido** (fora do escopo do pedido).

Os schemas foram renomeados (`summit` → `summit_2026`, `comum` → `ecossistema`), mas **21 funções**
continuaram apontando pros nomes velhos. Elas **quebram ao serem chamadas** — não é aviso, é erro
de "relation does not exist".

Já corrigidas (eram o caminho do contexto do agente): `public.treble_agent_context_base`,
`public.mind_virada_de_lote`.

**Ainda quebradas (19):**
`api.changed_since` · `api.event` · `api.knowledge` · `api.me` · `api.mindagent_bootstrap` ·
`api.my_agenda` · `api.sessions` · `api.speakers` · `api.treble_event_bundle` ·
`api.treble_find_location` · `api.treble_route` · `concierge.resumo_do_dia` ·
`public.mind_admin_dashboard_counts` · `public.mind_admin_mutate_resource` ·
`public.mind_admin_read_resource` · `public.mind_conteudo` · `public.mind_materiais_para` ·
`public.mind_precos_por_volume` · `public.mindagent_chat_search` · `public.mindagent_sync_offers`

Isso provavelmente derruba o app do Summit (as `api.*`), o painel admin (`mind_admin_*`) e a busca
do chat do site. **Vale conferir o que dessas ainda é usado** — talvez várias sejam lixo de
migração e devam ser apagadas em vez de corrigidas.

**Confirmado quebrando em produção AGORA:** o cron `mindagent-sync-precos` (job 1, a cada 30 min)
devolve `500 {"ok":false,"error":"rpc_falhou"}` em **toda** execução — bate em
`public.mindagent_sync_offers`, que está na lista das 19. Ou seja: a sincronização de preços não
roda desde a renomeação dos schemas.

Mapa de equivalência: `summit.events/sessions/offers/commercial_rules` → `summit_2026.*` ·
`summit.conhecimento` → `summit_2026.knowledge_documents` · `comum.speakers` →
`ecossistema.palestrantes_especialistas` (`cargo_curto`, `instituicao`; **sem** `destaque`) ·
`comum.taxonomy` → **não existe mais**.

---

## 9. Texto dos templates (HSM) vem vazio

**Status:** conhecido, não corrigido.

Mensagens de template do Treble guardam o texto em `hsm.message`; a ingestão
(`treble_sessao_encerrada_gravar`) lê só `text.message`. Resultado: o que a **empresa disparou**
entra com `conteudo` nulo.

Impacto real é baixo — nas conversas com resposta o transcrito está completo (83% do lado agente
tem texto), e os vazios são disparos de campanha sem conversa. Correção é ~1 linha
(`coalesce(text.message, hsm.message)`), mas mexe na ingestão: fazer com calma e reprocessar
`engagement.treble_eventos`.

---

## 10. Devolver "lead ruim" pro tráfego — investigado: **já existe casa no HubSpot**

**Status:** investigado (a pedido da Adriana). Não precisa criar propriedade nova.

O HubSpot **já tem** o vocabulário pra isso. Valores reais, conferidos na conta:

- **`motivo_do_lead__perdido`** (contato) — opções: Data do evento · Local do evento ·
  Valor do evento · **`Perfil desqualificado`** ← *é exatamente o "lead ruim / sem perfil"* ·
  Não retornou o contato · Descadastrar · Optou por encerrar conversa.
- **`icp`** — 6 perfis Mind: CHRO/VP de Pessoas · CEO/C-Suite · Gestor/Middle Manager ·
  People Leader/BP · Executivo Sênior · Consultor/Coach/Psicólogo.
- **`icp_confianca`** — número 0 a 10 (confiança da classificação).
- **`etapa_do_lead__atualizar`** — Novo lead · Lead em contato · Lead qualificado (rótulo
  "Comprou ingresso") · Em negociação · Lead perdido. **É a que a Treble já escreve hoje**
  (`hubspot_etapa_do_lead__atualizar = "Lead em contato"` aparece em `conversas.variables`).
- **`origem_do_lead`** — existe, mas com **uma opção só** (`eduzz`). Praticamente não usada.

**Então o desenho fica:** análise marca `lead_ruim` com motivo `sem_perfil` →
`motivo_do_lead__perdido = "Perfil desqualificado"`; a IA também pode preencher `icp` +
`icp_confianca`. O cruzamento com campanha usa a UTM que já está no espelho (1.015 contatos com
`utm_source`) — o tráfego lê isso por relatório/lista, sem propriedade nova.

**Lacuna do espelho:** `icp_confianca`, `origem_do_lead` e `etapa_do_lead__atualizar` **não estão**
em `crm.contato_espelho`. Pra ler/escrever com segurança, o sync precisa trazer as três.

**A decidir com a Adriana:** a IA pode escrever `motivo_do_lead__perdido` e `icp`, ou isso fica
como sugestão pra revisão humana?

---

## 11. Ingresso que NÃO vem de venda Eduzz: reconciliar os dois vocabulários  ⭐ PRÓXIMO

**Status:** o vocabulário **já existe** (28/08) — não precisa ser criado. Falta reconciliar e
completar. **Decisões de negócio pendentes com a Adriana.**

Com o catálogo do `mind-hubpost` e o credenciamento espelhados, a origem do ingresso está
classificada em **dois lugares, com palavras diferentes**:

| onde | campo | valores |
|---|---|---|
| `eduzz.produto_catalogo` | `tipo_de_acesso` | Pago (92) · Cortesia (38) · **Patrocínio (17)** |
| | `tipo_de_venda` | Eduzz (102) · **Direta (12)** · Não é venda (55) |
| | `motivo_concessao` | Convidado (21) · Parceria (9) · Palestrante (2) · Imprensa (1) |
| | `origem_do_acesso` | `Mind` (29) ou o patrocinador nominal (Beiersdorf, Vale, Natura…) |
| `credenciamento_summit_2026.participantes` | `ticket_origin` | Pago (992) · Cortesia (27) · **Convidado institucional (8)** · **Staff (1)** |
| | `ticket_type` | Mind (360) · VIP (298) · **SEM MAPA (213)** · Prime (157) |

### Mapeamento incompleto — ✅ esperado, **pendência da Adriana** (28/08)

Ela confirmou: **está tudo certo, vai completar depois.** Não é bug nem buraco de encanamento —
é trabalho de conteúdo que ainda não foi feito. Fica registrado só pra ninguém "consertar" por
conta própria nem se assustar com o número:

- **1.904 vendas sem mapeamento** — juntando `eduzz.vendas.id_do_produto` →
  `produto_catalogo.eduzz_product_id`, casam 1.078 Pago + 178 Cortesia + 47 Patrocínio.
- **213 participantes com `ticket_type = "SEM MAPA"`** — produto ainda não mapeado em
  `credenciamento_produtos_mapa` na origem (33 linhas, só `Pago`/`Cortesia`,
  `empresa_patrocinadora` 100% vazia).

Conforme ela for mapeando no `mind-hubpost` e no projeto Vendas, o espelho pega sozinho no
próximo ciclo — **não precisa fazer nada aqui.** Pra reconferir a cobertura a qualquer momento,
a consulta está em `docs/CORE_UNIVERSAL.md`, §15.

**O que continua em aberto de verdade — as perguntas que só a Adriana responde:**
1. **Qual vocabulário é o oficial?** Catálogo diz `Patrocínio`; credenciamento diz
   `Convidado institucional` e `Staff`. *(Sugestão: o do catálogo, porque classifica o **produto**
   e não a pessoa — vale pra todo mundo que comprar aquele SKU. É chute meu, não fato.)*
2. `tipo_de_venda = Direta` (12 produtos): venda fora da Eduzz? Onde é registrada hoje?
3. Patrocínio: o patrocinador ganha N ingressos por contrato? Quem nomeia as pessoas, e quando?

**Tabelas do projeto Vendas ainda NÃO espelhadas** (não foram pedidas; ficam registradas pra não
redescobrir): `cortesia_requisicoes` · `receita_participantes` (~120) · `ingressos_gerados` (~1.071) ·
`espelho_lotes_map` (67) · `credenciamento_produtos_mapa` (33 — **já tem porta de leitura aberta**,
fonte `cred_produtos_mapa`; é uma linha pra espelhar).

Contexto do sistema em `docs/CORE_UNIVERSAL.md`.

---

## 12. Intelligence / Product Intelligence — ⏸️ DEFERIDO PARA NÃO BLOQUEAR O VENDEDOR (29/08)

**Por que está no backlog:** a investigação foi feita e trouxe decisões e dados úteis, mas completar
Ecossistema, palestrantes, taxonomia, conteúdo editorial, concierge e auditoria agora atrasaria o
go-live do agente comercial. **Não reinvestigar do zero quando retomarmos.** Este bloco é o checkpoint.

**Checkpoint técnico:** investigação posterior ao merge da PR #16; `main` naquele ponto =
`cd551c802570e5358e6bcb55d702c539ba0fe28b`.

### 12.1 Decisões canônicas já fechadas

- **ECOSSISTEMA = Intelligence perene, curada e reutilizável do Mind** entre Summit, Institute,
  Dash e futuros produtos/agentes.
- **PRODUCT INTELLIGENCE = verdade específica e atual de cada produto/evento.**
- **KNOWLEDGE = conteúdo explicativo / long-tail.**
- **OFFER / COMMERCIAL CURRENT REALITY = preço, lote, checkout, regra comercial atual.**
- **PLAYBOOK = como pensar.**
- **AGENT_CONTEXT = pessoa, CRM, engagement e realidade da pessoa/conversa.**
- `ecossistema.palestrantes_especialistas` é **LOCAL_AUTHORITATIVE**, não mirror do Summit.
  A Adriana está deliberadamente curando e inserindo essa tabela diretamente no banco.
- Participação no Summit e dossiê do especialista são conceitos diferentes:
  `summit_2026.session_speakers` diz **quem participa de qual sessão**; `ecossistema` diz **quem é
  a pessoa e qual a inteligência perene sobre ela**.
- Autoria manual não é erro quando o Mind é deliberadamente a autoridade. O risco é conteúdo sem
  proveniência, fato mutável duplicando source externa, geração automática sem revisão, ou conteúdo
  antigo ainda ativo.
- **Não criar linhas vazias de especialista para “completar cobertura”.** Ausência hoje é
  `CURADORIA_ECOSSISTEMA_PENDENTE`, não mirror quebrado.

### 12.2 Estado real do schema `ecossistema` — já investigado

Hoje `ecossistema` tem **uma tabela de dados**:

- `palestrantes_especialistas`: **31 linhas**;
- `palestrantes_especialistas_id_seq`;
- `slugify(text)`;
- trigger function `palestrantes_slug_bi()`;
- trigger `trg_palestrantes_slug` BEFORE INSERT/UPDATE;
- PK `id`, unique `slug`, unique `lower(btrim(nome))`;
- única FK externa: `summit_2026.session_speakers.speaker_id → ecossistema.palestrantes_especialistas.id ON DELETE SET NULL`;
- leitores encontrados: `public.mindagent_chat_search` e `public.treble_agent_context_base`;
- **nenhum writer automático**: nenhuma function, Edge, job ou cron escreve na tabela;
- grants só a `postgres`; escrita administrativa direta é coerente com a curadoria atual.

Não existe hoje tabela de conceitos, construtos, fundamentos científicos ou outra Intelligence
perene dentro de `ecossistema`. **Não criar essas tabelas antecipadamente.**

### 12.3 Proveniência dos 31 registros — evidência já levantada

O que a investigação prova:

- migration criou/evoluiu o schema, mas **não existe INSERT/UPDATE de conteúdo em migration**;
- nenhum script versionado, Edge Function, function, job ou cron escreve os 31 registros;
- os 31 `criado_em` são distintos ao longo de ~23h, compatíveis com inserção um a um;
- só **2/31** têm `atualizado_em > criado_em`;
- no Drive existe **`Prompt inteligencia palestrantes`**, criado em 24/08, cujo formato obrigatório
  corresponde às colunas da tabela; o primeiro registro nasceu 12 segundos depois da criação do doc;
- o prompt exige pesquisar **um palestrante por vez**, verificar fontes/DOIs e não preencher lacunas
  por inferência;
- o conteúdo segue majoritariamente essa especificação: `A prova:` 25/31; `Por que isso importa:`
  24/31; abertura obrigatória de aprendizado 27/31; 5 seções ICP 29/31; `fontes_gerais` com URL 30/31;
- o escape `Não localizado em fonte confiável` aparece **0/31**.

O que NÃO está provado tecnicamente: quem/qual ferramenta executou a pesquisa. Não registrar
“foi IA” ou “foi humano” como fato sem log. A autoridade da tabela decorre da decisão explícita da
Adriana de que ela está curando e inserindo essa Intelligence.

**Registro incompleto conhecido:** Ivana Moreira (id 29): vazios em
`relevancia_para_os_icps`, `principais_livros`, `principais_papers`,
`limites_e_cuidados_cientificos`, `fontes_gerais`.

### 12.4 Natureza dos campos de `palestrantes_especialistas`

- **Identidade/fato:** `nome`, `aliases`, `cargo_curto`, `instituicao`.
- **Derivado/técnico:** `id`, `slug`, `criado_em`, `atualizado_em`.
- **Editorial/científico/estratégico Mind:** `quem_e`, `formacao_e_posicao`,
  `principais_contribuicoes`, `conceitos_chave_explicados`, `por_que_o_conteudo_e_importante`,
  `o_que_posso_esperar_ouvir_e_aprender`, `dores_e_problemas_que_ajuda_a_compreender`,
  `relevancia_para_os_icps_do_mind`, `limites_e_cuidados_cientificos`.
- **Referência/evidência:** `principais_livros`, `principais_papers`, `fontes_gerais`.

Cobertura levantada: `nome`, `cargo_curto`, `instituicao`, `quem_e`, `formacao_e_posicao`,
`principais_contribuicoes`, `conceitos_chave_explicados`, `por_que_o_conteudo_e_importante`,
`o_que_posso_esperar_ouvir_e_aprender`, `dores_e_problemas_que_ajuda_a_compreender` = 31/31;
`aliases` = 8/31; `relevancia_para_os_icps_do_mind` = 29/31; referências/fontes principais = 30/31.

**Não existe hoje proveniência por linha/campo** além de timestamps. Isso fica para a auditoria;
não adicionar coluna agora só por antecipação.

### 12.5 Line-up Summit × Ecossistema — não refazer esta comparação

A investigação corrigiu a premissa antiga:

- `speakers.json` é representação do line-up e autoridade **da grafia**, não SOURCE do dossiê;
- `design/README.md` declara a referência mobile congelada como fonte de verdade de conteúdo/copy;
- `programacao.json` declara a planilha `programacaomindsummit2026.xlsx` como origem;
- o dossiê do especialista **não descende** de `speakers.json`/programação.

Cobertura já medida:

- `speakers.json`: **54 nomes**;
- nomes reais citados na programação: **56**;
- já curados no Ecossistema: **30**;
- `CURADORIA_ECOSSISTEMA_PENDENTE`: **24** vs `speakers.json`, **26** vs programação;
- 1 especialista do Ecossistema fora do line-up atual: **Márcio Atalla** — saiu do evento; permanecer
  no Ecossistema é **correto**, não anomalia.

Variantes de nome já consideradas inequívocas:

- Arthur Guerra → Arthur Guerra de Andrade (id 10);
- Cirlene Zimmermann → Cirlene Luiza Zimmermann (id 13);
- Daniel de Barros → Daniel Martins de Barros (id 15);
- Igor Menezes → Igor Gomes Menezes (id 23);
- Reinaldo Costa → Reinaldo Xisto Vieira Costa (id 30; alias já explícito).

Casos ambíguos conhecidos: **Sibelle Pedral** e **Virginie Leite**. A referência congelada contém
registro malformado e o site atual interpreta papéis de forma diferente. Não resolver por fuzzy.

### 12.6 `session_speakers` — números preservados para retomar sem nova investigação

Estado investigado:

- **61 vínculos** totais;
- **9 resolvidos** com `speaker_id`;
- **52 pendentes**;
- **31 vínculos são resolvíveis hoje** porque a pessoa já está curada no Ecossistema;
- portanto existem **+22 vínculos líquidos** que podem ser feitos sem criar conteúdo;
- esses 31 vínculos fariam **18 dossiês curados** hoje invisíveis passarem a aparecer no retrieval Summit;
- **16 vínculos** dependem apenas da conclusão da curadoria de **13 pessoas**;
- **14 vínculos** têm outro problema de identidade/relação/programação.

As 13 pessoas que travam os 16 vínculos:
`Denise Salvador`, `Irene Reis`, `Maryana com Y`, `Mauro Muller`, `Michelle Schneider`,
`Oscar de Bos`, `Paul Goldsmith`, `Paula Benevides`, `Renata Rivetti`, `Sibelle Pedral`,
`Tamara Myles`, `Veruska Galvão`, `Yuri Trafane`.

Os 14 casos restantes estão ligados a divergências da programação. Sessões já apontadas:

- `A virada da diversidade` (16/09 12:30): banco 2 vínculos; programação 4 nomes;
- `A nova era da alta performance` (16/09 12:30): banco 2; programação 1;
- `Mulheres que abrem caminho` (17/09 12:30): banco 1; programação 2;
- `Alta performance começa por dentro` (16/09 17:20): banco 3; título divergente;
- `Lançamento livro Carla Tieppo` (17/09 13:30): banco 1; site `Autógrafos Carla Tieppo`;
- `Sessão especial` (17/09 16:40): 2; fonte malformada;
- `Mind Talks` (17/09 17:20): 2; papéis discordam;
- `Sessão especial` (17/09 16:00): 1; sem correspondência.

Também já foi medido: **8 sessões do banco não existem no site e 10 entradas do site não existem
no banco**. O antigo `palestrante_id` UUID é irrecuperável: tabela-alvo foi apagada, temp de import
foi dropada e o namespace UUID v5 não foi preservado.

**Quando retomar:** a menor mudança de relação já identificada é resolver explicitamente os +22
vínculos cujo especialista já existe, sem fuzzy e sem criar dossiê. Isso ficou adiado apenas porque
não é caminho crítico do vendedor agora.

### 12.7 Taxonomia/conceitos perenes — investigação já feita, implementação adiada

Foi descoberto que uma camada de conceitos **já existiu e foi apagada**:

- `mind.taxonomy` → depois `comum.taxonomy`;
- 10 temas conhecidos: `seguranca_psicologica`, `dados_bem_estar`, `regulacao`,
  `lideranca_humana`, `cultura`, `saude_mental`, `performance`, `diversidade`, `felicidade`,
  `futuro_trabalho`;
- `comum.taxonomy` foi apagada fora de migration;
- evidência sobrevive em `dados/summit.json.temas` e
  `archive/pre-architecture/missing-migrations/20260820205324_...sql`.

Efeitos vivos já observados:

- `summit_2026.sessions.trilhas`: **0/67**;
- `summit_2026.sessions.topicos_aprendizado`: **0/67** na investigação mais recente;
- `treble_agent_context_base.visao_geral.trilhas`: `[]`;
- `treble_agent_context_base.visao_geral.publico_e_dores`: `'[]'::jsonb` hardcoded com comentário
  de que `comum.taxonomy` não existe mais.

**Não reconstruir agora.** Quando houver necessidade real, decidir a casa perene correta dentro de
Ecossistema e reutilizar o que a investigação já encontrou.

### 12.8 Contradição conhecida no retrieval de especialistas

`public.mindagent_chat_search` hoje filtra especialista por
`exists(session_speakers.speaker_id = pt.id)`. Isso faz a Intelligence perene depender de
participação no Summit.

Efeito medido na investigação: **3/31 dossiês alcançáveis e 28/31 invisíveis** naquele estado.
Um especialista do Institute sem sessão no Summit seria invisível por construção.

Isso contradiz a decisão canônica de Ecossistema compartilhado. **Não corrigir isoladamente agora**;
revisitar quando o Kit Loader/retrieval for legitimamente tocado, porque o contexto da rota deve
decidir quais fontes perenes são relevantes — não um gate implícito de participação no Summit.

Dívida documental separada já conhecida: comentário inline dentro de `mindagent_chat_search`
ainda descreve incorretamente `ts_rank_cd` como cobertura de termos. Corrigir na próxima alteração
legítima da função ou no fechamento da etapa, não reaplicar SQL só por comentário.

### 12.9 Legado ainda ligado a `comum.speakers`

A investigação mais recente encontrou **8 funções** ainda lendo a tabela apagada
`comum.speakers`:

`api.speakers` · `api.sessions` · `api.mindagent_bootstrap` · `api.treble_event_bundle` ·
`api.changed_since` · `mind_admin_read_resource` · `mind_admin_mutate_resource` ·
`mind_admin_dashboard_counts`.

Não corrigir em massa. Quando retomar, classificar consumidor real vs legado e corrigir/apagar
proporcionalmente. Este achado é mais recente e específico para speaker do que o inventário histórico
da seção 8 acima.

### 12.10 Riscos de proveniência/conteúdo já identificados — auditoria adiada, não esquecida

Não é auditoria de mérito ainda; é mapa de risco para o retorno:

- `cargo_curto` e `instituicao` são fatos mutáveis; hoje não há data de consulta nem origem por linha;
- 1/31 sem `fontes_gerais` (Ivana Moreira);
- alguns registros fogem parcialmente do protocolo editorial (`A prova`, `Por que isso importa`,
  abertura e seções de ICP);
- o escape `Não localizado em fonte confiável` aparece 0/31 e deve ser auditado, não interpretado;
- só 2/31 mostram revisão posterior via timestamp;
- não existe campo de revisor/data de consulta/versão;
- geração automática sem revisão **não foi comprovada nem descartada**;
- conteúdo antigo/legado ainda ativo deve ser procurado;
- fatos operacionais mutáveis hardcoded são risco maior do que autoria manual deliberada.

**Gate de fechamento da Intelligence/Product Intelligence:** antes de considerar essa camada
confiável/completa, fazer auditoria guiada de:

1. todos os fatos hardcoded relevantes;
2. conflitos entre sources/mirrors/textos ativos;
3. proveniência do conteúdo ativo;
4. conteúdo ruim/inventado/sem fonte;
5. conteúdo desatualizado;
6. lacunas reais do que o agente deveria saber.

Essa auditoria será conduzida em linguagem de negócio, conceito por conceito; não exigir que a
Adriana navegue tabela por tabela. **Não bloqueia o primeiro go-live comercial.**

### 12.11 Source Registry / Intelligence Management — decisão congelada, partes futuras no backlog

Comportamento aprovado:

- **novo conteúdo numa fonte já registrada** → fica disponível ao Kit Loader sem mudança de código
  do agente;
- **nova fonte/tabela** → nunca é autoativada;
- quando possível, o sistema poderá fazer **auto-discovery**, criar uma pendência e usar IA para
  propor classificação;
- humano aprova, ajusta ou ignora;
- só depois a fonte entra no **Source Registry** e passa a poder ser consumida pelo Kit Loader.

Fluxo futuro aprovado:

`AUTO-DISCOVERY → pending → proposta de classificação → aprovação humana → Source Registry → Kit Loader`.

**Não construir agora** o frontend nem o cron/autodiscovery completo. O futuro frontend deve ser
uma **Inbox da Intelligence**, não uma tela técnica: mostrar o que apareceu, o conceito provável,
produto/scope, natureza (SOURCE/MIRROR/LOCAL_AUTHORITATIVE/DERIVED), autoridade e permitir
`APROVAR / AJUSTAR / IGNORAR`.

O `Source Registry + Kit Loader mínimo` que destrava o vendedor é **trabalho corrente do roadmap,
não item adiado deste backlog**. O que fica aqui é a automação/UX posterior.

### 12.12 Critério de retorno — ordem sugerida quando o vendedor já estiver funcionando

Não refazer descoberta. Retomar a partir destes pontos, conforme necessidade real:

1. corrigir/reconciliar Product Intelligence que realmente afete produto em uso;
2. reparar +22 `session_speakers` determinísticos quando isso trouxer valor;
3. continuar a curadoria do Ecossistema no ritmo da Adriana — sem geração automática de dossiês;
4. resolver os 14 casos de programação divergente somente contra a source atual;
5. decidir se/como reconstruir conceitos/taxonomia perene quando houver consumidor real;
6. corrigir o gate de retrieval do Ecossistema dentro do Kit Loader, não como exceção Summit;
7. classificar/remover legado `comum.speakers`;
8. construir auto-discovery + Intelligence Inbox quando a operação já justificar;
9. executar a auditoria final de hardcodes, proveniência, conflitos e lacunas antes de declarar a
   Intelligence completa/confiável.

**Prioridade atual que justificou o adiamento:** construir o sistema extensível → Kit comercial
mínimo do Summit → Decisioning de vendas → Agent → handoff → Treble E2E → vendedor funcionando.

---

## 13. Infra de deploy GitHub — descoberta 29/08/2026

**Status:** fato verificado, **já incorporado ao contrato operacional v4** (`PROJECT_STATE.md` §2B).
**Não é uma frente para redesenhar agora. Não reinvestigar esses fatos do zero.**

**Por que apareceu:** o checkpoint v3 afirmava `Produção continua separada e controlada.` O sistema
real contradiz literalmente essa frase.

### O que foi provado

- **Cloudflare Git integration está ativa.** Ao abrir PR, o Cloudflare Workers criou preview da
  branch automaticamente.
- **Merge em `main` gerou build de produção.** O commit de merge recebeu o check
  `Workers Builds: mind-agent`, com `details_url` no ambiente `production` e **Version ID novo**.
- A descrição do próprio GitHub App da Cloudflare, no check, declara que ele **faz deploy
  automaticamente quando uma PR é mergeada**.
- **Supabase GitHub integration está ativa.** O próprio check do GitHub App do Supabase declara que
  ele **roda migrations automaticamente quando PRs são mergeadas** e **cria preview DBs para novas
  PRs**.
- `Supabase.list_branches` do projeto `ymnmotgglsrxmjmonwjz` mostrou a branch default `main` com
  `git_branch = main`.

### Consequência já registrada

Isso virou o contrato canônico **MERGE EM `main` É BOUNDARY DE DEPLOY** em `PROJECT_STATE.md` §2B
(checkpoint v4): revisão/teste antes do merge; gate explícito da Adriana antes do merge nas
mudanças sensíveis; verificação pós-deploy só do efeito diretamente afetado.

### Pendência futura — somente se quisermos mudar esse modelo

Hoje a trava é **operacional** (regra em `PROJECT_STATE.md`), não física. Se um dia quisermos travas
físicas, avaliar:

- branch protection / ruleset em `main` (required reviews, required checks, restrição de quem
  mergeia);
- configurações das próprias integrações Cloudflare e Supabase (o que dispara preview, o que dispara
  produção, quais paths).

**Gatilho para retomar:** quando o modelo operacional deixar de bastar — por exemplo, mais gente
mergeando, incidente de deploy indevido, ou necessidade de separar ambiente de produção de fato.
Enquanto isso não acontecer, a regra operacional v4 é a resposta e este bloco é só memória.

---

## 14. Play / experiência do Concierge — o que ficou de fora hoje (Lane E, 30/08/2026)

**Status:** investigado e verificado contra o sistema real. A **coleta** do Play foi implementada
(ver `supabase/migrations/20260830231500_lane_e_play_coleta.sql`); os itens abaixo **não** foram, e
cada um tem um motivo factual. **Não reinvestigar do zero.**

### O que já existe e foi reutilizado (para não ser redescoberto)

- **Superfície real do Play** = o app público na raiz do repositório (`index.html`, `app.js`,
  `styles.css`, `config.js`, `chat-service.js`, `data-service.js`), publicado por Cloudflare Workers
  (`wrangler.jsonc` → `cloudflare/worker.ts`, assets em `dist-cloudflare/`). Ele fala com duas Edge
  Functions: `mindagent-bootstrap` (programação) e `mindagent-chat` (conversa). **Não existe outro
  frontend/backend do Play.** O `/admin` é o painel, não o Play.
- **Casas de coleta** já existiam e já apontam para `pessoas.pessoas(id)`: `engagement.sessao_feedback`
  (UNIQUE participante_id+sessao_id), `engagement.nps` (UNIQUE participante_id), `engagement.evento_feedback`,
  `engagement.feedbacks` (tipo/valor/contexto) e `engagement.jornada_sessao`. Todas com zero linha.
- **Contratos das ferramentas do Play** já existiam congelados em `concierge.ferramentas` (28
  ferramentas ativas, com `json_schema`), incluindo `registrar_feedback_sessao`, `registrar_nps`,
  `registrar_feedback_evento`, `registrar_feedback`, `confirmar_presenca` e `enviar_material`.
  `concierge.config` (23 chaves), `concierge.feature_flags` (13), `concierge.templates` (40) e
  `concierge.regras_proativas` (18) também já estão povoados.
- **O que faltava e foi feito:** nenhuma função escrevia nessas casas — `concierge.ferramenta_chamadas`
  tinha zero linha e não havia runtime executando as ferramentas registradas.

### 14.1 Slides / materiais — SEM FONTE

`public.mind_materiais_para(text,text,text,text)` lê `comum.materiais`, **tabela que não existe**
neste banco (o schema `comum` virou `ecossistema`, sem tabela de materiais). É uma das 19 funções
apontando para schemas antigos já registradas na seção 8 deste backlog. `summit_2026.knowledge_documents`
tem 17 linhas e coluna `url`, mas é conhecimento explicativo, não repositório de slides por sessão.

**Por que foi deferido:** o `PASSO 11B` proíbe fabricar material inexistente, e não há source real
para apontar. Criar uma tabela de materiais sem conteúdo aprovado seria inventar requisito.

**DECISÃO FECHADA (supervisão, 30/08/2026 — issue #43).** O Drive conectado foi verificado: há
materiais do Summit espalhados, mas **não existe fonte canônica por sessão/palestra** que possa ser
ligada com segurança. Portanto:

- `slides/materiais` fica **deferido até existir source explícito**;
- **não bloqueia o go-live do Play**;
- **não criar tabela nem mirror vazio** enquanto não houver source.

**Gatilho para retomar:** aparecer uma fonte canônica por sessão/palestra. Aí é `SOURCE → MIRROR`
normal, não tabela autoral nova.

**Dependência:** existir o source; não é mais uma pergunta em aberto para a Adriana.

### 14.2 AMA / perguntas sobre conteúdo — depende da Lane C

`summit_2026.knowledge_chunks` tem **zero linha**; `knowledge_documents` tem 17. O retrieval vivo é
`public.mindagent_chat_search`, consumido pela `mindagent-chat` — **componente da Lane C** durante o
paralelo.

**Por que foi deferido:** responder pergunta de conteúdo é retrieval, e o dono do retrieval nesta
rota é a Lane C. Abrir aqui criaria segundo caminho de busca.

**Gatilho para retomar:** Lane C fechar o retrieval factual do Concierge.

### 14.3 Ofertas contextuais Institute/Dash — falta a regra, não a fonte

`summit_2026.offers` tem 25 linhas; existem `institute.knowledge_documents` e `dash.knowledge_documents`.
A ferramenta `registrar_sinal_comercial` já está registrada e a flag `sinal_comercial` está **desligada**;
`concierge.config.sinal_comercial` exige evidência literal e consentimento para contato.

**Por que foi deferido:** `PASSO 11B` só autoriza oferta contextual "baseada em regra aprovada", e a
regra de quando/como ofertar Institute/Dash dentro do evento não está congelada. Regra comercial é
gate da Adriana.

**Gatilho para retomar:** a regra de oferta aprovada e registrada.

### 14.4 Humor como camada de copy — é conteúdo

`concierge.prompts` (7) e `concierge.templates` (40) já são a casa da linguagem. Nada foi escrito lá.

**Por que foi deferido:** prompt e copy são conteúdo da Adriana; o agente de código não inventa voz.
Humor também não pode virar licença para afirmar fato — e a camada factual está fora desta lane.

**Gatilho para retomar:** texto fornecido/aprovado pela Adriana.

### 14.5 Presença em sessão (`confirmar_presenca`) — casa existe, writer não

`engagement.jornada_sessao` existe (PK participante_id+sessao_id, com `planejou`, `compareceu`,
`fonte_presenca`, `confianca_presenca`, `motivo_ausencia`) e está vazia. A ferramenta
`confirmar_presenca` já está registrada.

**Por que foi deferido:** presença/jornada é insumo de memória e de resumo do dia, território da
**Lane D** no paralelo. Escrever aqui arriscaria dois writers para a mesma casa. O `retrato` do NPS
já lê `jornada_sessao` — quando ela for povoada, o retrato melhora sozinho, sem mudar código.

**Gatilho para retomar:** Lane D definir quem escreve jornada/presença.

### 14.6 Pergunta aberta de produto — coleta anônima

`engagement.evento_feedback.participante_id` e `engagement.feedbacks.participante_id` são **nuláveis**;
`sessao_feedback` e `nps` são **NOT NULL**. O app abre sessão anônima quando a Yazo não entrega
e-mail (`chat-service.js` → `auth/v1/signup`), e nesse caso não há `pessoa_id`.

Os writers implementados **exigem pessoa** nos quatro casos, por uniformidade e para manter
idempotência.

**DECISÃO FECHADA — v1 NÃO aceita coleta anônima (supervisão, 30/08/2026 — issue #43).**

Os writers permanecem **person-bound**. Sem `pessoa_id`, a coleta não executa — os writers já
devolvem `sem_pessoa`/`pessoa_nao_encontrada`, que é exatamente o comportamento decidido.

Explicitamente **fora de escopo em v1**, para não inventar arquitetura em cima de uma decisão
mínima: device identity, reconciliação posterior de anônimo → pessoa, e segunda idempotência.
Esta é a menor solução coerente com as casas atuais (`sessao_feedback` e `nps` já têm
`participante_id NOT NULL`).

**Gatilho para reabrir:** só se a operação do evento provar perda relevante de coleta por causa de
participante não identificado. Aí volta pelo ritual normal, como decisão nova de produto.

### 14.7 Drift: `summit_2026.sessions.site_session_id` existe em produção e não na cadeia de migrations

**Status:** descoberto pelo preview branch da PR #48 (Lane E, 30/08/2026). **Não corrigido — fora do
escopo da lane.** Registrado para não ser redescoberto.

**Evidência.** `summit_2026.sessions.site_session_id` está presente em produção
(`ymnmotgglsrxmjmonwjz`) e é tratada em vários documentos como a chave determinística contra
`programacao.json.id`. Mas `grep -rn site_session_id supabase/migrations/` **não encontra nenhuma
migration que a crie**. No preview branch da PR #48 (`igyobrssxhfauesxnljx`), montado replicando a
cadeia versionada, `summit_2026.sessions` **não tem a coluna** — a consulta falha com
`42703: column s.site_session_id does not exist`.

Ou seja: a coluna entrou em produção fora da cadeia versionada, ou por uma versão que hoje é stub
histórico no-op. Qualquer banco montado a partir das migrations — preview, ambiente novo, restore —
não a tem.

**Impacto imediato já tratado:** `public.mind_play_nps_agregado` foi escrita sem depender dela.

**Impacto ainda aberto:** qualquer código que leia `site_session_id` funciona em produção e quebra em
preview. Vale conferir o que já depende dela antes de assumir que só a Lane E encostou no assunto.

**Por que foi deferido:** `summit_2026.sessions` não é da Lane E; mexer nela aqui seria limpeza
lateral e conflito com quem é dono da tabela.

**Gatilho para retomar:** quando alguém precisar de `site_session_id` num banco que não seja
produção, ou na faxina de reconciliação da cadeia de migrations. A correção é uma migration aditiva
e idempotente (`alter table ... add column if not exists`), não um backfill de dado.

**Dependência:** dono de `summit_2026.sessions` (frente da programação/Concierge).

### 14.8 `public.mindagent_bootstrap` quebrada bloqueia o vínculo canônico do Play

**Status:** descoberto ao preparar a superfície de coleta no app (Lane E, 30/08/2026).
**Não corrigido — fora do escopo da lane.** É o bloqueio concreto do Definition of Done do Play.

**Evidência.** Chamar `public.mindagent_bootstrap('mind-summit-2026')` em produção falha com
`42P01: relation "summit.events" does not exist`. A função lê `summit.events`, `summit.sessions`,
`summit.locations`, `summit.session_speakers.palestrante_id` (coluna legada), `comum.speakers` e
`comum.taxonomy` — schemas renomeados (`summit` → `summit_2026`, `comum` → `ecossistema`) e, no caso
de `comum.taxonomy`, **schema que não existe mais**. É uma das 19 funções já listadas na §8.

**Consequência em cadeia, que é o que importa aqui:**

1. a Edge Function `mindagent-bootstrap` devolve 503;
2. `data-service.js` cai no `useLocalFallback` e o app roda inteiro no `dados/summit.json`;
3. esse arquivo tem **53 sessões** (produção tem 77) e ids **slug** (`d1-09_00-abertura`), não uuid;
4. logo **o app não tem o `sessao_id` canônico** para vincular nada a `summit_2026.sessions`.

Sem esse id, `mind_play_feedback_sessao` recusa com `sessao_nao_encontrada` — corretamente. O
`play-service.js` antecipa a recusa como `sessao_sem_id_canonico` para a tela poder ser honesta.

**Atenção ao consertar:** `'id', coalesce(s.yazo_id, s.id::text)` faz o `yazo_id` ganhar do id
canônico quando existe. Só reapontar os schemas **não** resolve o Play: o contrato do app precisa
carregar o uuid canônico de `summit_2026.sessions` (como campo próprio, se `yazo_id` tiver de
continuar sendo o `id` público). `comum.taxonomy` não existe mais, então `temas` precisa de decisão
sobre o que passa a alimentá-lo.

**Por que foi deferido:** a função serve o app inteiro (programação, pessoas, temas), não só o Play;
consertá-la envolve decidir o destino de `temas` sem `comum.taxonomy`. Fazer isso dentro da Lane E
seria limpeza lateral e atropelaria quem é dono da programação.

**Gatilho para retomar:** é pré-requisito para o Play coletar feedback vinculado a sessão. Deve
entrar antes do E2E do Play.

**Dependência:** dono da programação/bootstrap + decisão sobre `temas`.
