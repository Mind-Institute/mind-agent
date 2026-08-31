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

## 14. `public.mind_lead_capturar` — RESOLVIDO em 30/08/2026: era chamada morta, foi removida

**Status:** **fechado.** Descoberto pela Lane B do go-live, investigado pela Lane D na #42,
removido na #47. Não é frente aberta. Não reinvestigar.

### POR QUE APARECEU

A Lane B ia acrescentar uma chave (`rota`) ao `p_contexto` dessa chamada e foi conferir o
contrato da função antes de mexer. Ela não tem contrato: não existe.

### O QUE FOI PROVADO

- `treble-inbound-agent` chamava `public.mind_lead_capturar` em todo turno com pessoa.
  Varredura em `pg_proc` por `proname ilike '%lead%'` em **todos os schemas** devolve
  apenas `crm.registrar_lead(...)` e as janelas `pg_catalog.lead`. **A função nunca
  existiu.**
- O erro era engolido de propósito (`console.error({event:"lead_capturar_falhou"})` e
  segue), então nenhum turno quebrava — o write-back é que nunca acontecia.
- A investigação da **#42 (Lane D, dona do write-back)** fechou que é **chamada morta,
  não função faltante**: todo o payload já tem casa canônica **no mesmo turno**. Criar a
  RPC duplicaria estado, e `crm.registrar_lead` não é substituto compatível — outra
  assinatura, outro schema, e quebrada.
- Conferido contra as 5 conversas reais do agente em produção: `participante_id`,
  `session_external_id`, `agente` e `produto_codigo` em 5/5; `audience`, `stage`,
  `variables.intent` e `variables.needs_human` em 4/5 — a quinta nunca teve turno de
  agente. `ticket_interest`, `objection` e `desfecho` são nulos por natureza quando não
  se aplicam. `origem_codigo` e `utm` estão em zero conversas do agente vivo, ou seja, a
  chamada morta carregava null para eles de qualquer forma.

Mapa de destino de cada campo que ela carregava:

| campo | casa canônica |
|---|---|
| pessoa · referência · agente | `engagement.conversas` (`participante_id`, `session_external_id`, `agente`) |
| origem · utm · produto | `engagement.conversas` |
| audience · stage | `engagement.conversas`, por `mind_turno_registrar` |
| intent · ticket_interest · objection · desfecho · needs_human | `engagement.conversas.variables`, idem |
| rota | `engagement.mensagens.blocos`, no meta do turno (a partir da v1.4.0) |

### O QUE FOI FEITO

A chamada saiu do `treble-inbound-agent` na PR #47, **sem nenhum writer no lugar** —
essa foi a instrução da Lane D. O comentário no runtime preserva o mapa acima, para que
ninguém "conserte" a ausência criando a RPC. `tests/vendedor_summit_smoke.mjs` traz a
consulta que prova campo a campo, no E2E, que a superfície persistida não perdeu nada.

### O QUE ISSO NÃO RESOLVE

Write-back de verdade continua sendo o **Passo 15B / PASSO 9** do runbook, com a Lane D
como dona, e o item 6 deste backlog como levantamento. Quando ele for construído, nasce
da casa canônica — não de uma função com a assinatura desta chamada morta.

---

## 15. Lane D — pós-turno / memória / write-back / continuidade

Investigação da issue #42 (go-live, execução paralela). **Não reinvestigar estes fatos do zero.**
O que foi implementado nesta lane está na §15.1; o que ficou deferido, da §15.2 em diante, com o
gatilho de retomada de cada um.

Retrato do sistema real no momento da investigação (produção, projeto `ymnmotgglsrxmjmonwjz`):

| capacidade | estado | evidência |
|---|---|---|
| análise pós-turno | **viva** | `analisar-conversa` + cron 12 (`*/15`, ativo); 395 linhas em `intelligence.analise_conversa`; 9 conversas pendentes no momento da medição |
| memória universal | **escrita, nunca lida** | 886 linhas em `intelligence.participante_memoria`, 286 pessoas; nenhum leitor no turno |
| write-back / dispatch | **parcial** | só `status_summit_2026`, via `treble_status_*` + ledger `crm.status_summit_hs` (67 linhas), crons 10/11 |
| continuidade / Silence | **construída, desligada** | cron 13 `silence_reavaliar` `active = false`; `silence_sync_from_analysis` continua mantendo o estado (395 linhas em `intelligence.continuidade_comercial`) |

O caminho de escrita do pós-turno está inteiro e é este:

```text
cron 12 → analisar-conversa → analise_montar_contexto
  → analise_classificador (lista de analisadores)
  → prompt do analisador → analise_gravar
       ├── analise_projetar_memoria  → intelligence.participante_memoria
       └── silence_sync_from_analysis → intelligence.continuidade_comercial
```

### 15.1 O circuito de memória estava aberto no lado da leitura — FECHADO nesta lane

**O que foi provado.** `intelligence.participante_memoria` tem 886 linhas de 286 pessoas, todas
projetadas por `analise_projetar_memoria` a partir de `dados.customer_memory`. Buscando em
`pg_get_functiondef` de todo `public`/`intelligence`/`agentes`/`engagement`, os únicos consumidores
da tabela são o próprio writer e `mindagent_chat_save_interests` (que também escreve). **Nenhum
componente do runtime lê a memória.** `mind_agent_context` não a compõe — e o comentário da própria
função já dizia, desde o Passo 8, `Memory entra no Passo 15`.

**A menor mudança.** Um coletor a mais, na forma dos quatro que já existem:
`public.mind_memoria_fatos(p_pessoa_id uuid) → jsonb`. Sem tabela nova, sem writer novo, sem
arquitetura paralela.

**Semântica congelada da leitura** (está no comentário da função e na migration):

- `ativa` e `proposta` saem em listas **separadas** (`memorias` / `propostas`). Fundir as duas
  transformaria inferência fraca em fato, que é o que o Passo 15 proíbe;
- `substituida` e memória expirada (`valido_ate` no passado) **nunca saem** — viram contagem em
  `meta`, para a ausência ser legível;
- há **dois writers com duas formas de `valor`** — `{text, scope}` do analisador e
  `{label, confirmed}` da superfície de chat. O coletor devolve `valor` cru e deriva
  `texto = coalesce(text, label)`; `escopo` fica nulo quando o writer não gravou escopo. Nenhuma
  terceira forma foi inventada.

**O que ficou de fora de propósito.** A migration **não** altera `mind_agent_context`. O CONTRATO 3
de `tests/mind_agent_context_contract.sql` trava o conjunto **exato** de chaves do topo, e aquele é
o caminho síncrono compartilhado. O coletor entra pronto e desligado.

**Atualização (31/08/2026) — o coletor passou a filtrar pelo marcador.** Ele expõe **somente**
linhas com `valor.sensitivity = 'none'`, o marcador que os dois writers seguros gravam (§16). Assim
as 886 memórias do contrato v1 ficam fisicamente preservadas e invisíveis ao Agent, sem apagar nem
reescrever nada, e revalidar o legado vira incremental. Ausência de marcador não é silenciosa: vira
`meta.sem_marcador_ignoradas`.

**Como retomar (o wiring).** Determinado na **§15.6** contra os runtimes reais de B e C; a trava é
a política da §15.3. Registro original: quem integrar o runtime decide onde a memória entra —
`mind_agent_context` (e aí o CONTRATO 3 e o comentário da função precisam ser atualizados no mesmo
passo) ou direto no Decisioning/Agent, sem tocar o contrato do Passo 8. **Enquanto essa linha não
existir, memória continua sem voltar no turno seguinte** — o coletor sozinho não fecha o critério
de pronto do PASSO 8 do go-live.

### 15.2 `analise_pendentes` só enxerga o Treble — DEFERIDO em 30/08/2026

> Superseded em parte pela **§15.7**, que fecha o encanamento do pós-turno do Concierge contra a
> superfície real da Lane C. Esta seção fica pelo levantamento numérico.

**POR QUE APARECEU.** Verificando se o Concierge de hoje teria memória pós-turno.

**O QUE JÁ FOI PROVADO.** `public.analise_pendentes` filtra
`c.agente in ('treble','treble-inbound-agent')`. A distribuição real de `engagement.conversas` é:
`treble` 6.896 (400 com mensagem de lead), `treble-inbound-agent` 5 (4 com lead),
`agente = null` + canal `mindagent-web` 23 (19 com lead), `mindagent-chat` 13 (0 com lead).
**As 19 conversas web com mensagem de lead nunca entraram na fila de análise**, e uma rota de
concierge que não grave `agente` como Treble também não entrará.

**ESTADO ATUAL.** Todas as 395 análises são `analise_vendas_summit`. Os slots
`analise_concierge`, `analise_atendimento`, `analise_contexto_geral`, `analise_vendas_institute` e
`analise_vendas_dash` existem em `agentes.prompts` com `conteudo` vazio e `ativo = false`
(confirmado: `length = 0`). `analise_prompt` só devolve prompt ativo e não-vazio, e o
`analisar-conversa` cai no fallback `analise_contexto_geral` — que também está vazio.

**POR QUE FOI DEFERIDO.** Alargar o filtro **sozinho** não produz análise de concierge: as
conversas entrariam na fila, o classificador as mandaria para `analise_concierge`, não haveria
prompt, e o resultado seria chamada de LLM gasta e `sem_prompt`. As duas metades têm de andar
juntas, e a que falta é conteúdo da Adriana (§3 deste backlog).

**COMO RETOMAR.** Quando `analise_concierge` (ou o fallback `analise_contexto_geral`) estiver
preenchido e ativo: alargar o filtro de `analise_pendentes` para incluir as conversas da superfície
de concierge/web, e só então medir a fila. É mudança de uma cláusula `where`.

**DEPENDÊNCIAS / GATILHO.** Prompt de análise do concierge preenchido pela Adriana.

### 15.3 Política de sensibilidade da memória — investigada a fundo, BLOQUEADA por conteúdo

**POR QUE APARECEU.** Decisão 4 da supervisão: memória não vai ao Agent antes de a política de
sensibilidade funcionar. Esta seção é a investigação que sustenta essa decisão.

#### Existe memória sensível persistida hoje? O scan NÃO responde isso.

> **CORREÇÃO (30/08/2026).** Este bloco afirmava "não existe memória sensível persistida hoje".
> **Está errado e não deve ser reusado.** O scan prova apenas que **aquele scan não identificou
> nenhum caso** — não que não exista nenhum. A diferença é material, e o próprio achado abaixo
> explica por quê: se a distinção entre "é psicóloga clínica" e "está afastada por burnout" não
> está nas palavras, então uma varredura por palavra não pode ser exaustiva, e um caso redigido
> fora do vocabulário previsto passaria despercebido pelo mesmo método.
>
> **Consequência:** as 886 linhas legadas continuam **sem autorização de exposição ao Agent**. A
> proposta mínima de revalidação está na §16.6 (PR de memória segura).

Varredura determinística das 886 linhas contra as 10 categorias de `intelligence.memoria_bloqueios`
(saúde, diagnóstico, medicação, afastamento, religião, opinião política, orientação sexual, origem
racial, filiação sindical, saúde de terceiro). **11 candidatos, e os 11 são falso-positivo** — o
padrão deles é a descoberta que importa:

| o que casou | por quê |
|---|---|
| "Coach e Mentora de Carreira / Psicóloga", "estudante de Psicologia" (×2), "é psicóloga clínica com atuação em Terapia Cognitivo-Comportamental", "é estudante de fisioterapia" | **profissão**, não saúde |
| "Rosane Obino Psicologia", "Agir Com-Ciência Psicologia", "empresa informada: Muito Além do meu Diagnóstico" | **nome de empresa** |
| "quer entender se o evento é direcionado a psicólogos clínicos" | **interesse comercial** |
| "é estudante de Psicologia e mencionou que isso influencia a decisão por preço/desconto" | **objeção comercial** |
| "trocou o ce**lula**r e não encontrou o convite" | colisão de substring com `lula` |

#### Por que um filtro por palavra é a mecânica errada aqui

Este é um evento de saúde mental. **O vocabulário do domínio é o vocabulário da profissão do
público.** "psicóloga", "terapia", "burnout", "diagnóstico" são exatamente o que o vendedor precisa
saber sobre a pessoa — e são exatamente as palavras de um gate por regex. Um bloqueio textual
erraria nos dois sentidos ao mesmo tempo:

- **destruiria memória comercial legítima** — "é psicóloga clínica" é qualificação, não dado de
  saúde;
- **não pegaria a divulgação real** — "estou afastada por burnout" é indistinguível de "quero
  conteúdo sobre burnout" para uma regex, e só a primeira é dado do art. 11 da LGPD.

A diferença entre as duas não está nas palavras: está em **quem é o sujeito e o que a frase afirma**.
Isso quem sabe no momento da extração é o analisador.

#### Onde a política tem de ser aplicada

**Na escrita, não na leitura.** Filtrar na leitura não protege nada: o dado sensível já teria sido
persistido em `intelligence.participante_memoria`, e a tabela sobrevive ao filtro. O ponto correto é
`public.analise_projetar_memoria`, que é o único caminho de entrada da memória do analisador.

Duas metades, e só uma é minha:

1. **Encanamento (determinístico, sem decisão de produto).** `analise_projetar_memoria` hoje **não
   consulta** `memoria_regras` nem `memoria_bloqueios` — verificado em `pg_get_functiondef`: ela
   deriva `tipo` de `category`, `chave` de `tipo || ':' || mind_slug(texto)` e `status` de
   `scope`/`confidence`, e nada mais. Ligar o gate é uma condição a mais no laço.
2. **Conteúdo (da Adriana).** Para o gate ter o que ler, o analisador precisa **rotular** a
   sensibilidade. `analise_vendas_summit` v1 já emite `category`, `scope` e `confidence`, mas
   **não tem nenhuma menção a sensibilidade/LGPD** (verificado por busca no corpo do prompt). O
   `analise_classificador` v2 também não.

#### Por que a taxonomia existente não pode ser "só tornada funcional"

Instrução era não inventar taxonomia nova se a existente servisse. Ela não serve, e o motivo é
concreto: as três tabelas usam **três vocabulários que não se cruzam**.

| tabela | vocabulário de `chave` | exemplo |
|---|---|---|
| `memoria_bloqueios` | categoria de sensibilidade | `saude_do_titular`, `religiao` |
| `memoria_regras` | tema de perfil/comportamento | `area_profissional`, `interesses`, `senioridade` |
| `participante_memoria` (real) | `tipo:slug(texto)` | `identidade`, `cargo_atual`, `interesse:quer_ver_a_grade` |

Um `join` por `chave` entre elas não casa com nada hoje. Fazê-las valerem exige decidir **de onde
vem a classificação** — categoria emitida pelo analisador × derivação determinística — e isso é
decisão de política, não de encanamento.

**PERGUNTA EXATA PARA A ADRIANA:** o `analise_vendas_summit` passa a emitir, por item de
`customer_memory`, um rótulo de sensibilidade no vocabulário que já existe em
`intelligence.memoria_bloqueios.chave` (`saude_do_titular`, `diagnostico_titular`,
`medicacao_titular`, `afastamento_titular`, `religiao`, `opiniao_politica`, `orientacao_sexual`,
`origem_racial`, `filiacao_sindical`, `saude_de_pessoa_citada`, ou nenhum)? Se sim, o encanamento
que descarta o item na escrita é pequeno e determinístico, e entra sem mais nenhuma decisão.

#### Um TTL que parecia de graça e NÃO é — `scope = 'temporary'` carrega opt-out

`valido_ate` é nulo nas 886 linhas: nenhum TTL é aplicado. `memoria_regras.estado_momentaneo`
prevê `ttl_dias = 1` ("cansaço, fome, pressa"). O analisador emite `scope` com três valores —
`stable` (230), `opportunity` (639), `temporary` (17) — e a tentação era mapear
`temporary → ttl_dias = 1` sem decisão nenhuma.

**Seria um erro grave.** Lidas uma a uma, as 17 linhas `temporary` não são estado momentâneo:

- 11 são **não-participação declarada** ("não pretende participar do Mind Summit neste ano",
  "declarou que não vai ao Summit este ano", …);
- 1 é **opt-out explícito** — "solicitou descadastro após a primeira abordagem";
- 2 são logística de origem (o popup de saída do site), que não é temporário;
- 1 é um compromisso datado ("pretende falar com o diretor até amanhã");
- 2 são o resto.

Expirar isso em 24h apagaria justamente o registro de que a pessoa **pediu para não ser
procurada** — e a memória de opt-out é a que mais precisa durar. É o mesmo defeito do D1 do
Silence, na mesma origem: **o rótulo do analisador drifou da semântica que o motor espera**.

Nenhum TTL foi ligado. Fica dependente da mesma decisão de conteúdo acima.

### 15.4 Silence — decomposição exata dos `stopped` (CORRIGE um número reportado antes)

**CORREÇÃO.** O checkpoint anterior desta lane disse "264 de 395 (67%) fora da fila" como se fosse
tudo efeito do D1. **Está errado e não deve ser reusado.** 264 estão fora da fila, mas a maioria
está fora *corretamente*. `last_decision.calculo.reason_code` guarda o motivo de cada uma, e ele
decompõe os 264 sem ambiguidade:

| `reason_code` | linhas | o que é |
|---|---|---|
| `purchase_confirmed_crm` | 38 | **intencional** — prova de compra no banco |
| `purchase_declared` | 47 | **intencional** — a pessoa declarou compra |
| `opt_out` | 66 | **intencional** — `summit_motivo_exclusao` |
| `stopped` | **113** | **o bug D1** — `dados.continuation_status = 'stopped'` sem razão da seção 22 |

**151 das 264 (57%) estão fora da fila porque devem estar.** O D1 explica **113**, ou 28,6% das
395 — não 67%.

Isso é estrutural, não coincidência: a precedência da `silence_calcular_next_review` testa compra e
opt-out **antes** de olhar o `continuation_status` do analisador. Quando a execução chega ao ramo 3,
já está provado que não houve compra nem opt-out — ou seja, o ramo 3 só vê o caso ambíguo.

#### Quanto custa o D1 — simulação determinística, sem enviar nada

`silence_calcular_next_review` é `STABLE` e recebe `p_dados` por parâmetro. Dá para calcular o que
cada uma das 113 viraria **se o `stopped` sem razão da seção 22 deixasse de valer**, chamando a
própria função de produção com `dados - 'continuation_status'`. Leitura pura: nada foi gravado,
nenhuma mensagem foi enviada, o cron 13 continua desligado.

Resultado das 113:

| viraria | linhas | efeito |
|---|---|---|
| `silence` / `timing_matrix` | **95** | **entra na fila de reavaliação** |
| `commitment_pending` / `commitment_due` | **1** | **entra na fila** |
| `silence` / `event_trigger_only` (`no_legitimate_recontact_reason`) | 14 | fica fora — correto, não há motivo legítimo de recontato |
| `stopped` / `purchase_confirmed_crm` | 3 | fica fora — compraram depois da análise |

**96 oportunidades entrariam na fila; 17 continuariam fora, corretamente.** Das 113, 99 têm
`open_loop` real, 43 têm `purchase_intent` alto/médio e 38 têm `commercial_priority` urgente/alta.

A simulação também prova que as travas funcionam: ninguém que comprou ou pediu descadastro é
puxado de volta — a precedência os retém antes do ramo do D1.

#### Onde a correção pode ser feita — duas opções, ambas decisão da Adriana

1. **No prompt** (o que o §2 propôs): dizer que `stopped` só vale para a seção 22, e que conversa
   encerrada com ponto aberto é `silence`.
2. **No ramo 3 de `silence_calcular_next_review`**: parar de tratar `stopped` sem `reason_code`
   como parada definitiva.

As duas mudam quem recebe follow-up, então as duas são decisão de produto. **Nada foi alterado.**
O que esta lane entrega é o número exato e a simulação repetível.

#### O que continua igual

D2 e D3 do §2 seguem abertos e inalterados. `followup_count` é 0 nas 395 — coerente com o D3
(ninguém envia), então `DORMANT por followup_exhausted` continua não podendo acontecer de verdade.
Cron 13 `active = false`.

### 15.5 `public.mind_lead_capturar` não existe — e a menor correção é NÃO criá-la

Achado da Lane B (PR #47), que o registrou e passou adiante como write-back. Esta lane investigou o
que deveria acontecer. **A conclusão é contraintuitiva e vale ler antes de escrever qualquer
função.**

#### O que está quebrado

- `treble-inbound-agent` v1.3.0 (no ar) chama `supabase.rpc("mind_lead_capturar", {p_pessoa_id,
  p_agente, p_referencia, p_contexto})` em **todo turno com pessoa identificada**.
- `public.mind_lead_capturar` **não existe** (`pg_proc` em todos os schemas).
- O erro é engolido: só `console.error({event:"lead_capturar_falhou"})`.
- Zero ocorrências no log de Edge das últimas 24h — mas isso **não prova que funciona**: a função
  teve **0 requisições** na mesma janela. A evidência é o catálogo, não o log.

#### A investigação: para onde esse payload deveria ir?

Campo a campo, contra o que o runtime já persiste:

| campo de `p_contexto` | onde já é persistido | por quem |
|---|---|---|
| `origem` | `engagement.conversas.origem_codigo` | `treble_agent_start`, na ingestão |
| `utm` | `engagement.conversas.utm` | idem |
| `produto` | `engagement.conversas.produto_codigo` | idem |
| `audience` | `engagement.conversas.audience` (coluna) | `mind_turno_registrar` |
| `stage` | `engagement.conversas.stage` (coluna) | `mind_turno_registrar` |
| `intent`, `ticket_interest`, `objection`, `needs_human`, `desfecho` | `engagement.conversas.variables` | `mind_turno_registrar` |
| `rota` (acrescentado pela Lane B) | `engagement.mensagens.blocos` da mensagem do agente | `mind_turno_registrar` → `mind_mensagem_registrar(p_blocos := p_meta)` |
| `p_pessoa_id` | `engagement.conversas.participante_id` | ingestão |
| `p_agente` | `engagement.conversas.agente` | ingestão |
| `p_referencia` (sessionId) | `engagement.conversas.session_external_id` | ingestão |

**Não sobra um único campo.** E `mind_turno_registrar` é chamada **no mesmo turno, poucas linhas
depois**, com exatamente o mesmo estado. Inclusive a `rota` que a Lane B acrescentou: o comentário
dela no PR #47 diz, com todas as letras, que a rota fica em `blocos` da mensagem do agente —
"nenhuma coluna nova, nenhuma segunda casa".

#### Conclusão

`mind_lead_capturar` é **chamada morta**, não função ausente. Criá-la construiria uma segunda casa
para um estado que já tem casa canônica — exatamente o que o `CLAUDE.md` proíbe ("uma casa por
conceito"). **A menor correção correta é remover a chamada**, não implementá-la.

A remoção é em `supabase/functions/treble-inbound-agent/index.ts`, que é **arquivo da Lane B**.
Esta lane não o tocou: passou o achado adiante.

**RESOLVIDO em 30/08/2026 — a Lane B removeu a chamada** na v1.4.0 do `treble-inbound-agent`
(PR #47, head `8401faf`), com o comentário no lugar do bloco citando esta investigação e a tabela
de casas canônicas acima. Não há writer novo no lugar, que é o correto: o estado já estava sendo
persistido. Quando o Passo 15B construir o write-back de verdade, ele nasce da casa canônica.

**O que continua aberto:** o 15B em si (mapeamento `buyer_state` → `hs_pipeline_stage`, gate da
Adriana) e a dupla órfã abaixo.

**Se a intenção original era outra** (enfileirar o lead para criação de card no HubSpot, que é o
Passo 15B), então a chamada está no lugar errado de qualquer forma: o payload é estado de turno,
não dado de lead (não tem e-mail, telefone, `utm_source`, `fbclid`), e não corresponde à forma de
`crm.leads_capturados`. O 15B continua precisando do mapeamento `buyer_state` → `hs_pipeline_stage`,
que é gate da Adriana.

#### Descoberta lateral: `crm.registrar_lead` também está quebrada

Não é escopo desta lane e **não foi corrigida** — registrada para não ser redescoberta:

- `crm.registrar_lead(...)` insere em `crm.leads_capturados (email, whatsapp, primeiro_nome,
  sobrenome, empresa, cargo, agente, contexto)`;
- a tabela real tem `(id, firstname, lastname, email, phone, company, perfil_d_cliente,
  botao_selecionado_no_site, utm_*, fbclid, gclid, msclkid, li_fat_id, estado, criado_em,
  enviado_em)`;
- executá-la falha com `42703: column "whatsapp" of relation "leads_capturados" does not exist`
  (verificado);
- `crm.leads_capturados` tem **0 linhas** e **nenhuma outra função a lê**.

A forma da tabela (utm/fbclid/gclid/`estado` pendente→`enviado_em`) é de **fila de captação do
site para o HubSpot**, não de sinal comercial de conversa. Função e tabela estão órfãs juntas.

---

### 15.6 Onde `mind_memoria_fatos` entra no runtime — delta preparado, NÃO ativado

Determinado contra os runtimes reais das Lanes B e C, não contra a arquitetura imaginada.

**Superfícies vivas, depois de B e C:**

| runtime | rota | o que monta o contexto |
|---|---|---|
| `treble-inbound-agent` (Lane B, PR #47) | vendedor B2C/B2B | `treble_agent_context` + `mind_agent_kit` + Router/Gate |
| `mindagent-chat` (Lane C, PR #50) | concierge | `mindagent_chat_get_context` + `mindagent_chat_search` |

A Lane C **não criou superfície nova**: o PR #50 troca o corpo de `public.mindagent_chat_search`
mantendo assinatura e chaves, e os consumidores continuam sendo `mindagent-chat` e o bloco de
agenda do `treble-inbound-agent`.

**Onde a memória deve entrar.** Não em `mind_agent_context`: o CONTRATO 3 de
`tests/mind_agent_context_contract.sql` trava o conjunto exato de chaves do topo, e mexer nele
altera o caminho síncrono compartilhado pelas duas lanes no mesmo dia. O ponto certo é **um por
runtime, aditivo**:

- vendedor → junto do Kit, no `aiInput` do `treble-inbound-agent`, como bloco próprio
  (`memoria: mind_memoria_fatos(pessoa_id)`), ao lado de `quem_esta_falando`;
- concierge → em `mindagent_chat_get_context`, que **já lê `intelligence.participante_contexto`**
  (tabela com 0 linhas) e é o lugar natural: a memória real está em `participante_memoria`, não em
  `participante_contexto`.

**Nada disso foi ativado.** Duas travas, nesta ordem: a política de sensibilidade da §15.3 (decisão
4 da supervisão) e o fechamento dos runtimes de B e C. O coletor está pronto, testado e desligado
desde o PR #46.

Uma observação que vale para quem ligar: `mind_memoria_fatos` já ignora memória expirada, então no
dia em que o TTL da §15.3 passar a ser gravado o lado da leitura não precisa mudar.

---

### 15.7 Pós-turno do Concierge — encanamento definido, conteúdo faltando

Com o PR #50 no ar, a superfície do concierge é conhecida e o mapa fica exato:

1. **Quais conversas precisam entrar em `analise_pendentes`.** Hoje o filtro é
   `agente in ('treble','treble-inbound-agent')`. As conversas do concierge são
   `canal = 'mindagent-web'`, e elas se dividem em duas populações com datas que não se
   sobrepõem:

   | `agente` | conversas | com mensagem de lead | período |
   |---|---|---|---|
   | `mindagent-chat` | 14 | 1 | 28/08 → 30/08 |
   | nulo | 23 | 19 | 21/08 → 27/08 |

   **O `agente` nulo é histórico, não defeito vivo:** a superfície web passou a carimbar
   `mindagent-chat` em 28/08 e não produziu mais nenhuma linha nula desde então. (Registro
   anterior desta seção dizia que a superfície "não está carimbando" — estava errado e não deve
   ser reusado.)

   Consequência prática: o filtro precisa apenas acrescentar `'mindagent-chat'`. As 19 conversas
   com lead e `agente` nulo são um lote fechado de antes de 28/08 — se entram ou não é decisão
   à parte, e o volume vivo hoje é pequeno (1 das 14).
2. **Qual analisador deveria ser escolhido.** O `analisar-conversa` já conhece `analise_concierge`
   na lista fechada `ANALISADORES`, e o `analise_classificador` v2 já pode devolvê-lo — o
   encanamento de seleção **existe e está pronto**.
3. **Que contrato de saída já existe.** `analise_gravar` deriva `funcao='concierge'` e
   `vertical=null` do nome do analisador (`mapear()` na Edge Function), grava em
   `intelligence.analise_conversa` e projeta `dados.customer_memory` em `participante_memoria` pelo
   mesmo caminho do vendedor. `silence_sync_from_analysis` ignora `funcao <> 'comercial'`, então
   análise de concierge **não contamina a fila de continuidade comercial** — já está correto.
4. **O que realmente falta.** Só o conteúdo: `agentes.prompts` tem `analise_concierge` v1 com
   `conteudo` vazio e `ativo = false`, e o fallback `analise_contexto_geral` também. `analise_prompt`
   só devolve prompt ativo e não-vazio, então hoje a conversa entraria na fila, o classificador a
   mandaria para `analise_concierge`, e o resultado seria chamada de LLM gasta e `sem_prompt`.

**Nada de prompt foi inventado.** Ordem correta quando o conteúdo existir: preencher/ativar o
prompt → alargar o filtro de `analise_pendentes` (uma cláusula `where`) → medir a fila. As duas
metades não andam separadas.

---

### 15.8 Decisão congelada — memória não vai ao Agent antes da política

Registro da decisão 4 da supervisão na issue #42, para não ficar só em comentário de GitHub:

> **Memória NÃO deve ser exposta ao Agent em produção antes de a política de sensibilidade estar
> funcionando na escrita.** O coletor `public.mind_memoria_fatos` pode continuar pronto e
> desligado.

Sustentada pela §15.3: `memoria_bloqueios` e `memoria_regras` não são aplicados por nenhum writer, e
o gate correto é na escrita, dependente de um rótulo que o analisador ainda não emite.

**Atualização (30/08/2026):** a pergunta da §15.3 foi respondida e aprovada. O contrato
(`sensitivity` no prompt v2) e a trava fail closed em `analise_projetar_memoria` estão implementados
na PR de memória segura — ver **§16**. A decisão acima **continua valendo para o legado**: as 886
linhas gravadas sob o contrato v1 não são expostas ao Agent até serem revalidadas (§16.6).
