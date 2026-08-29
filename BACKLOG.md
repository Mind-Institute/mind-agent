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

## 14. Runtime vivo do Treble — checkpoint da investigação do Passo 12B (29/08)

Registro do que foi **investigado e confirmado no sistema real**, para ninguém reinvestigar.
Nada aqui foi implementado. Divide-se em **caminho atual** (o que está no ar hoje) e
**dívida/deferimento** (o que ficou registrado para depois).

### Caminho atual — o runtime vivo do Treble

`treble-inbound-agent` v1.3.0 é o único caminho vivo do vendedor no WhatsApp. Por turno ele faz,
nesta ordem:

```
treble_agent_config()            → treble.config (token, modelo, timeout, flags)
treble_agent_start(...)          → ingestão + identidade + histórico + audience/stage
[em paralelo]
  treble_agent_context(5 args)   → IGNORA os 5 argumentos
  treble_agent_prompt(null)
  mindagent_chat_search(...)     → só se treble.config.bloco_agenda_busca = 'true'
treble_agent_resposta_repetida() → dedup de 90 s
treble_agent_prompt(audience)    → 2ª chamada, agora com a audiência
agendaSegura                     → filtro em TypeScript, 5 chaves
OpenAI Responses (json_schema strict, effort:none, store:false)
guardrail de preço (TS, regex R$)
treble_agent_identificar / mind_pessoa_completar / mind_lead_capturar / mind_turno_registrar
```

O payload ao LLM tem 6 chaves: `DADOS_OFICIAIS`, `AGENDA_E_PALESTRANTES`, `estado_da_conversa`,
`quem_esta_falando`, `historico`, `mensagem_do_lead`.

### O achado central — duas `treble_agent_context`

- **`treble_agent_context` (viva, reduzida)** devolve **somente** `evento` e `ofertas_vigentes`.
  Verificado no `prosrc`: **não referencia nenhum dos 5 parâmetros** que recebe
  (`p_audience`, `p_origem`, `p_utm`, `p_conversa`, `p_produto`).
- **`treble_agent_context_base` (ÓRFÃ, zero chamadores)** é a rica: `experiencias_o_que_inclui`,
  `faq`, `conteudo_aprovado`, `visao_geral`, `virada_de_lote`, `proximo_lote`,
  **`regras_comerciais`** e `politicas`.

Quem lê o código da `_base` conclui que o agente recebe FAQ, políticas e regras comerciais.
**Ele não recebe nada disso.** É o descompasso mais caro do sistema hoje.

### Órfãs que funcionam

Testadas nesta investigação, corretas, **zero chamadores**:

- **`mind_precos_por_volume()`** — devolve 4 faixas × 3 experiências com `faixa`,
  `valor_cheio_por_ingresso`, `valor_por_ingresso_com_desconto`, `economia_por_ingresso`,
  `parcelamento_com_desconto`. É **exatamente** o bloco `precos_por_volume` que o
  `playbook_summit_b2b` exige em DADOS_OFICIAIS.
- **`mind_virada_de_lote()`** — devolve `dias_restantes`, `ultimo_dia_do_lote_atual`,
  `pode_usar_como_urgencia`.

### Core canônico construído e fora do runtime

| componente | passo | estado |
|---|---|---|
| `mind_agent_context(uuid)` | 8 | **ÓRFÃ.** Substituída na prática pelo retorno de `treble_agent_start` |
| Edge `router` + `router_universal` | 10 | **ÓRFÃ.** Nunca chamada pelo inbound |
| `mind_rota_capacidade` | 11 | **ÓRFÃ.** Nunca chamada |

### `audience` legado usado como rota

A rota, hoje, é o campo `audience` que **o próprio LLM devolveu no turno anterior**, persistido em
`engagement.conversas.audience` e realimentado no turno seguinte. Taxonomia legada de 5 valores
(`b2c`, `b2b`, `cliente_suporte`, `ja_comprou`, `desconhecido`) — **não** a taxonomia canônica de 6
rotas. No primeiro turno ela é `desconhecido`.

**Decisão fechada (12B):** `audience` **não** pode virar fonte de verdade da rota no Core novo.

### Bloqueios comerciais — o dado existe, não é entregue

Tudo abaixo está no banco, ativo e correto. **Nada chega ao agente**, porque só existe dentro da
`treble_agent_context_base` órfã:

| bloqueia | onde está | quem lê hoje |
|---|---|---|
| desconto por volume (B2B) | `summit_2026.commercial_rules.desconto_por_volume` + `mind_precos_por_volume()` | ninguém |
| escada de desconto individual D1–D4 (B2C) | `summit_2026.commercial_rules.desconto_individual` | ninguém |
| políticas institucionais | `mind.policies` (6 linhas) | ninguém |
| virada de lote / próximo lote | `mind_virada_de_lote()`, `offers.inicia_em` | ninguém |

`commercial_rules` ativas (5): `desconto_por_volume` (tiers 5–9 = 10%, +10 = 20%, +15 = 30%,
+20 = 35%) · `desconto_individual` (4 níveis D1–D4 × 3 experiências, cada um com cupom e
`checkout_url` próprios) · `desconto_espontaneo` · `mencionar_cupom_nao_solicitado` ·
`insistencia_apos_desinteresse` (`max_retomadas: 1`).

Consequência prática: sem as regras de guarda, o `sales_decision_engine` (20 mil caracteres, ativo,
no prompt) opera **sem a tabela de condições que ele manda usar**. O guardrail de preço barra o
valor inventado e cai em `needs_human` — cada negociação de preço vira transferência.

### Outros achados que seriam caros de redescobrir

- **`mindagent_chat_search` preso a `agents={concierge}`.** O bloco `mind` (que carrega FAQ,
  ingresso e experiência) filtra por `'concierge' = any(k.agents)`. Os 17 documentos têm
  `agents = {concierge}` e `aprovado_treble = true`, então **funciona hoje** — mas o campo é
  legado e não é taxonomia canônica de applicability.
- **`agendaSegura`** (TypeScript) mantém só `sessions, speakers, locations, exhibitors, mind`.
  Descarta `event`, `offers` e `official_note` do retorno do `chat_search` — sem perda, porque os
  dois primeiros já chegam por `treble_agent_context`.
- **Prompt `base` não existe.** `treble_agent_prompt` procura `chave='base'` na ordem 1 e não
  acha: a composição perde silenciosamente o bloco de identidade e limites que ela supõe existir.
  As chaves reais são `playbook_router`, `tom_de_voz`, `sales_decision_engine`,
  `playbook_summit_<audience>`, `objecoes`.
- **Divergência de modelo:** `treble.config.openai_model = gpt-5.4` ·
  `intelligence.config.openai_model = gpt-5.4-mini` · `DEFAULT_MODEL = "gpt-5.4-mini"` no código
  da Edge. A config do Treble vence no inbound.
- **Flags sem efeito:** `treble.config.bloco_politicas` e `bloco_visao_geral` são lidas **apenas**
  pela função órfã. Ligadas ou desligadas, não mudam nada hoje.
- **8 funções legadas quebradas** apontam para `comum.speakers`, apagada fora de migration:
  `api.speakers`, `api.sessions`, `api.mindagent_bootstrap`, `api.treble_event_bundle`,
  `api.changed_since`, `mind_admin_read_resource`, `mind_admin_mutate_resource`,
  `mind_admin_dashboard_counts`. O caminho de escrita do painel está quebrado.
- **`checkout_url` conferem.** `offers` e os 3 documentos `ingresso` apontam para os mesmos links
  (`89AQDKYGWD`, `40Q3EKPK0B`, `E05XKB2KWX`). A escada D1–D4 usa produtos Eduzz **distintos**
  (`60E2ZOBBW3`, `6W4GEYV60Z`, `8017OQVK07`), com cupom embutido. Não há conflito a resolver.
- **`summit_2026.knowledge_documents`** já tem superfície de roteamento por linha: `agents text[]`,
  `produto_codigo`, `event_id`, `audiencia`, `cluster`, `tipo_conteudo`, `aprovado_treble`,
  `ativo`, `valido_de/ate`. `fonte_id` é uuid **sem FK** — aponta para uma tabela de fontes que
  nunca existiu.
- **Nenhuma estrutura existente serve de Source Registry.** `platform.llm_routes` roteia *modelo*
  e usa outra taxonomia de "rota" (`classificacao`/`conversa`/`recomendacao`/`resumo_dia`);
  `intelligence.config` é saco de segredos; `treble.config` é flag por canal;
  `concierge.ferramentas` (28 linhas) é registry de **ferramenta**, com `trilhas` vazio nas 28 —
  é o modelo de *forma* certo, não a tabela a reusar.
- **`engagement.conversas`** tem `canal`, `audience`, `produto_codigo`, `stage` — útil saber, mas
  ver a decisão acima: `audience` não vira rota canônica.

### Dívida / deferimento

- **12B.2** — wiring do Treble ao Core canônico (AGENT_CONTEXT, Router, Gate, Kit Loader). Não
  faz parte do 12B.1.
- **Gate desatualizado depois do Kit Loader.** `mind_rota_capacidade` decide kit por lista
  literal `('summit_b2c','concierge_summit')`. Quando o Kit Loader entregar `precos_por_volume`,
  o Gate passa a subestimar `summit_b2b`. Correção natural: o Gate consultar o Registry.
- **Prompt `base`** — decidir se cria a chave ou se remove a referência de `treble_agent_prompt`.
- **Modelo divergente** entre `treble.config` e `intelligence.config`.
- **FAQ comercial inexistente** — as 5 FAQs são logísticas (chegar/estacionar, tradução,
  masterclass, Mind×VIP, assento). Não há FAQ de parcelamento, reembolso, nota fiscal ou troca de
  titularidade. Conteúdo da Adriana, não encanamento.
- **Retrieval planner por LLM** — decisão fechada: determinístico primeiro, planner depois.
  O gargalo atual é entrega da Intelligence existente, não interpretação da pergunta.

Já registrados na seção 12 e **não repetidos aqui**: o gate de retrieval do Ecossistema e a dívida
do comentário inline de `mindagent_chat_search` (§12.8); as 8 funções legadas lendo `comum.speakers`
(§12.9); o comportamento aprovado do Source Registry e o fluxo de auto-discovery (§12.11).
