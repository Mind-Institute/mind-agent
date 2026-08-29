# Backlog — fila de desenvolvimento

Decisões pendentes e trabalho conhecido que **ainda não foi feito**. Não é roadmap nem promessa:
é a lista honesta do que ficou em aberto, pra ninguém redescobrir o mesmo buraco duas vezes.

Regra: item entra aqui quando a decisão é da Adriana (negócio) ou quando o encanamento existe mas
falta uma peça. Item sai daqui quando vira código no ar — ou quando a gente decide que não vale.

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

**Status:** decidido que **vale a pena**; falta construir.

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
