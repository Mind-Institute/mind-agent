# Backlog — fila de desenvolvimento

Decisões pendentes e trabalho conhecido que **ainda não foi feito**. Não é roadmap nem promessa:
é a lista honesta do que ficou em aberto, pra ninguém redescobrir o mesmo buraco duas vezes.

Regra: item entra aqui quando a decisão é da Adriana (negócio) ou quando o encanamento existe mas
falta uma peça. Item sai daqui quando vira código no ar — ou quando a gente decide que não vale.

---

## 1. Quem diz "já comprei" e não está no HubSpot

**Status:** aguardando decisão da Adriana. Sem prioridade definida.

Quando a pessoa clica **"Já comprei meu ingresso"** no WhatsApp, a regra em produção é:

- `summit__participacao_anual` tem **2026** → não escreve nada (já está na lista de compradores);
- não tem → escreve `status_summit_2026 = "Não engajou"` (a outra lista de exclusão de disparo).
- **Trava absoluta:** `summit__participacao_anual` **nunca** é escrito pelo sistema. Só compra real
  marca aquele campo.

**O buraco:** das 11 conversas com essa CTA, **9 pessoas não têm `hubspot_id`**. Elas existem em
`pessoas.pessoas` (ligadas pelo telefone), mas o telefone não casa com nenhum contato do HubSpot.
Sem id, não há onde escrever — então **essas 9 continuam recebendo disparo mesmo tendo dito que
já compraram**.

**Perguntar à Adriana:** o que fazer quando a pessoa declara que vai ao Summit e não achamos
`participacao_anual 2026`?
- mandar um e-mail (pra quem? avisando o quê?);
- conferir no sistema de **credenciamento** dela (fonte de verdade alternativa que o banco não vê);
- criar o contato no HubSpot pelo telefone;
- pedir o e-mail dentro da conversa, pra casar por e-mail;
- não fazer nada e aceitar a perda.

---

## 2. CTAs comerciais sem origem mapeada

**Status:** aguardando decisão da Adriana.

Só `"Quero saber mais"` está mapeada (→ `summit_exit_popup`, produto `mind-summit-2026`). As demais
CTAs reais que aparecem em `conversas.variables` seguem sem origem:

| CTA | conversas | é entrada comercial? |
|---|---|---|
| Ver condições | 3 | provável Summit — confirmar |
| Garantir meu ingresso | 3 | provável Summit — confirmar |
| Informação sobre o evento | 2 | provável Summit — confirmar |
| Descadastrar / Encerrar conversa | 4 | opt-out, **não** é origem |

Sem origem, o classificador pode ler essas conversas como ambíguas (foi exatamente o que acontecia
com "Quero saber mais" antes do contexto de origem).

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

## 4. Opt-out ("SAIR") sem tratamento

**Status:** não decidido.

Conversas cujo conteúdo é só `SAIR`/`Sair` hoje viram classificação normal (atendimento/concierge).
Deveriam provavelmente **excluir a pessoa de disparo** — mesmo mecanismo do item 1, mas por motivo
diferente (opt-out explícito, não compra). Não implementado.

---

## 5. Ranking do lead não está sendo calculado

**Status:** decisão de modelagem já tomada; cálculo não existe.

A fórmula acordada (pesos da Adriana) era: **conversa 40 · histórico de compra 30 · fit de empresa 30**,
com componente desconhecido virando neutro e o peso renormalizando; `lead_ruim` → descartar.

Na migração pro modelo canônico (1 linha por conversa × analisador, com `dados` jsonb), o
`ranking_conversa` foi removido — o estado comercial passou a ser o JSON do analisador. Hoje a
priorização vem do que o LLM devolve (`commercial_priority`, `purchase_intent`, `conversion_risk`),
**não** da fórmula ponderada com histórico de compra e porte de empresa.

**A decidir:** a fórmula volta como função sobre `dados` + CRM, ou a taxonomia do analisador basta?

---

## 6. Porte da empresa (fit) — enriquecimento externo

**Status:** não construído. Depende do item 5.

O HubSpot não tem porte de empresa garantido. A ideia era buscar via **Lusha** (MCP disponível) pelo
domínio do e-mail e guardar em `pessoas`. Gasta crédito → rodar só pra lead morno+.
Enquanto não existir, o componente "fit de empresa" fica neutro no ranking.

---

## 7. Write-back da análise pro HubSpot

**Status:** não construído.

O write-back que existe hoje cobre: status da conversa (24h) em Lead/Contato e
`status_summit_2026`. **Não** leva pro HubSpot o resultado da análise (estado comercial,
prioridade, próximo movimento, âncora de follow-up).

Falta decidir **quais propriedades** do HubSpot recebem isso (e criá-las lá).

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

## 9. Devolver "lead ruim" pro tráfego

**Status:** desenhado, não construído.

A ideia: quando a análise marcar `lead_ruim` (sobretudo **sem perfil** — veio do tráfego mas não
tem perfil de comprar um Mind), cruzar com a origem/UTM do contato (`utm_source`, `utm_campaign`,
`hs_analytics_source`, que **já existem** no espelho: 1.015 contatos com `utm_source`) e devolver
isso pro time de tráfego — pra ele saber **qual campanha traz lead sem perfil**.

Falta: decidir o canal (propriedade no HubSpot? relatório? lista?) e construir.
