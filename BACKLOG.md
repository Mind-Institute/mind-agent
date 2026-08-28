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

**Entrada de telefone** — normalização canônica `public.telefone_normalizar()` + gatilhos em
`pessoas.pessoas`, `engagement.conversas` e `treble.status_da_conversa`. Conserta o 9 do celular
(regra determinística: 8 dígitos começando em 6-9 = celular sem o 9), prepende DDI, devolve NULL
pro inválido. **3.432 números corrigidos**; era a causa das recusas do HubSpot.

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

## 8. Texto dos templates (HSM) vem vazio

**Status:** conhecido, não corrigido.

Mensagens de template do Treble guardam o texto em `hsm.message`; a ingestão
(`treble_sessao_encerrada_gravar`) lê só `text.message`. Resultado: o que a **empresa disparou**
entra com `conteudo` nulo.

Impacto real é baixo — nas conversas com resposta o transcrito está completo (83% do lado agente
tem texto), e os vazios são disparos de campanha sem conversa. Correção é ~1 linha
(`coalesce(text.message, hsm.message)`), mas mexe na ingestão: fazer com calma e reprocessar
`engagement.treble_eventos`.

---

## 9. Devolver "lead ruim" pro tráfego — investigado: **já existe casa no HubSpot**

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
